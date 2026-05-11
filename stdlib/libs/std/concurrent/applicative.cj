package std.concurrent

import std.sync.{AtomicUInt32, AtomicBool}
import std.concurrent.tasksmacro.*

// ====================
// Two tasks
// ====================

// Keep the original handwritten two-task implementation as a commented example of
// the declarations that `@GenerateTasks[2]` is expected to expand into.
// The handwritten three-task version has been removed; `Tasks3` and above should
// now only come from macro expansion.
/*
internal class Tasks2<T1, T2, S> <: Task<(T1, T2), S> & Takes<Unit> where S <: Spawner {
    let tasksLeft = AtomicUInt32(2)
    let failed = AtomicBool(false)
    var t1 = unsafe { zeroValue<T1>() }
    var t2 = unsafe { zeroValue<T2>() }

    Tasks2(t1: Task<T1, S>, t2: Task<T2, S>, spawner: S) {
        super(spawner)
        initNativeResources()
        t1.addFastContinuation(Tasks2_1(this))
        t2.addFastContinuation(Tasks2_2(this))
    }

    public func next(_: Unit): ?TaskChainLink {
        let outcome = (this.t1, this.t2)
        this.completeAndWaitContinuationsUnlocked(Success(outcome))
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

internal class Tasks2_1<T1, T2, S> <: Takes<T1> where S <: Spawner {
    Tasks2_1(let wrapped: Tasks2<T1, T2, S>) {}

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

internal class Tasks2_2<T1, T2, S> <: Takes<T2> where S <: Spawner {
    Tasks2_2(let wrapped: Tasks2<T1, T2, S>) {}

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

public func tasks<T1, T2, S>(task1: Task<T1, S>, task2: Task<T2, S>): Task<(T1, T2), S> where S <: Spawner {
    Tasks2(task1, task2, task1.spawner) // I really want to refactor this spawner business
}
*/

// ====================
// Macro-generated tasks
// ====================

@GenerateTasks[2]
struct _GenerateTasks2 {}

@GenerateTasks[3]
struct _GenerateTasks3 {}

@GenerateTasks[4]
struct _GenerateTasks4 {}

@GenerateTasks[5]
struct _GenerateTasks5 {}

@GenerateTasks[6]
struct _GenerateTasks6 {}

@GenerateTasks[7]
struct _GenerateTasks7 {}

@GenerateTasks[8]
struct _GenerateTasks8 {}

@GenerateTasks[9]
struct _GenerateTasks9 {}

@GenerateTasks[10]
struct _GenerateTasks10 {}

@GenerateTasks[11]
struct _GenerateTasks11 {}

@GenerateTasks[12]
struct _GenerateTasks12 {}

@GenerateTasks[13]
struct _GenerateTasks13 {}

@GenerateTasks[14]
struct _GenerateTasks14 {}

@GenerateTasks[15]
struct _GenerateTasks15 {}

@GenerateTasks[16]
struct _GenerateTasks16 {}
