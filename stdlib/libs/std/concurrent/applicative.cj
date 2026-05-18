package std.concurrent

import std.sync.{AtomicUInt32, AtomicBool}
import std.concurrent.tasksmacro.*


// =====================================
// Hand-written reference implementation
// =====================================
// Handwritten two-task implementation as a commented example of
// the declarations that `@GenerateTasks[2]` is expected to expand into.
/*
internal class Tasks2<T1, T2> <: Task<(T1, T2)> & Takes<Unit> {
    let tasksLeft = AtomicUInt32(2)
    let failed = AtomicBool(false)
    var t1 = unsafe { zeroValue<T1>() }
    var t2 = unsafe { zeroValue<T2>() }

    Tasks2(t1: Task<T1>, t2: Task<T2>, spawner: Spawner) {
        super(spawner)
        initNativeResources()
        t1.addFastContinuation(Tasks2_1(this))
        t2.addFastContinuation(Tasks2_2(this))
    }

    public func next(_: Unit): ?TaskChainLink {
        let outcome = (this.t1, this.t2)
        this.complete(Success(outcome))
        if (Thread.currentThread.hasPendingCancellation) {
            this.propagateFailureToContinuations(Excepted(TaskCancelledException()))
            return None
        }
        nextRunnableContinuation(outcome)
    }

    public func propagateFailure(fail: Failure): Unit {
        if (!this.failed.swap(true)) {
            // has not failed already
            this.complete(Fail(fail))
            this.propagateFailureToContinuations(fail)
        }
    }

    public func propagateFailureInline(fail: Failure): ?TaskChainLink {
        if (!this.failed.swap(true)) {
            // has not failed already
            this.complete(Fail(fail))
            this.propagateFailureToContinuationsInline(fail)
        } else {
            None
        }
    }
}

internal class Tasks2_1<T1, T2> <: Takes<T1> {
    Tasks2_1(let wrapped: Tasks2<T1, T2>) {}

    public func next(t: T1): ?TaskChainLink {
        this.wrapped.t1 = t
        if (this.wrapped.tasksLeft.fetchSub(1) == 1) {
            // this was the last one
            // this.wrapped.failed should also be false, but maybe add check?
            RunnableContinuation(this.wrapped, ())
        } else {
            None
        }
    }

    public func propagateFailure(fail: Failure): Unit {
        this.wrapped.propagateFailure(fail)
    }

    public func propagateFailureInline(fail: Failure): ?TaskChainLink {
        this.wrapped.propagateFailureInline(fail)
    }
}

internal class Tasks2_2<T1, T2> <: Takes<T2> {
    Tasks2_2(let wrapped: Tasks2<T1, T2>) {}

    public func next(t: T2): ?TaskChainLink {
        this.wrapped.t2 = t
        if (this.wrapped.tasksLeft.fetchSub(1) == 1) {
            // this was the last one
            RunnableContinuation(this.wrapped, ())
        } else {
            None
        }
    }

    public func propagateFailure(fail: Failure): Unit {
        this.wrapped.propagateFailure(fail)
    }

    public func propagateFailureInline(fail: Failure): ?TaskChainLink {
        this.wrapped.propagateFailureInline(fail)
    }
}

public func tasks<T1, T2>(task1: Task<T1>, task2: Task<T2>): Task<(T1, T2)> {
    Tasks2(task1, task2, task1.spawner) // I really want to refactor this spawner business
}
*/

// ====================
// Macro-generated tasks
// ====================

@GenerateTasksUpTo[16]
struct _GenerateTasks {}
