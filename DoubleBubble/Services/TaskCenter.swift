import SwiftUI

/// Long-running work, in one place the whole window can see.
///
/// Until this existed, the only sign that anything was happening was a small
/// spinner inside whichever button was pressed. That is honest for an Electron
/// launch, which takes a fraction of a second — and useless for a
/// `bundleCopy`, which copies and re-signs several hundred megabytes while the
/// interface says nothing at all. Worse, closing the sheet that started the
/// work left it running with nothing anywhere reporting it.
///
/// Jobs registered here survive the view that started them, so a duplicate or
/// a batch keeps going when its sheet is dismissed and stays visible in the
/// toolbar until it finishes.
@MainActor
final class TaskCenter: ObservableObject {

    static let shared = TaskCenter()

    struct Job: Identifiable, Equatable {
        let id = UUID()
        /// What is being done, in the user's words: "Duplicating “claude 2”".
        var title: String
        /// Which step it is on right now: "Copying settings".
        var detail: String?
        /// 0…1 when the size is known up front, `nil` for an indeterminate spinner.
        var fraction: Double?
        /// Bytes, when this is a copy — lets the detail line say "4,8 of 10,5 MB".
        var copied: Int64?
        var total: Int64?
        var isCancellable: Bool

        static func == (lhs: Job, rhs: Job) -> Bool { lhs.id == rhs.id }
    }

    @Published private(set) var jobs: [Job] = []

    /// Cancellation handlers, kept out of `Job` so the struct stays `Equatable`
    /// and cheap to diff in a view body.
    private var cancellers: [Job.ID: () -> Void] = [:]

    private init() {}

    var isBusy: Bool { !jobs.isEmpty }

    /// The one to show when the toolbar has room for a single line.
    var headline: Job? { jobs.first }

    @discardableResult
    func begin(
        title: String,
        detail: String? = nil,
        fraction: Double? = nil,
        cancel: (() -> Void)? = nil
    ) -> Job.ID {
        let job = Job(
            title: title, detail: detail, fraction: fraction,
            copied: nil, total: nil, isCancellable: cancel != nil
        )
        jobs.append(job)
        if let cancel { cancellers[job.id] = cancel }
        return job.id
    }

    func update(_ id: Job.ID, detail: String? = nil, fraction: Double? = nil) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let detail { jobs[i].detail = detail }
        if let fraction { jobs[i].fraction = fraction }
    }

    /// Progress expressed in bytes, which also fills in the fraction.
    func update(_ id: Job.ID, copied: Int64, total: Int64, detail: String? = nil) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].copied = copied
        jobs[i].total = total
        jobs[i].fraction = total > 0 ? min(1, Double(copied) / Double(total)) : nil
        if let detail { jobs[i].detail = detail }
    }

    func finish(_ id: Job.ID) {
        jobs.removeAll { $0.id == id }
        cancellers[id] = nil
    }

    func cancel(_ id: Job.ID) {
        cancellers[id]?()
    }

    func cancelAll() {
        for id in jobs.map(\.id) { cancellers[id]?() }
    }
}
