package std.concurrent

import std.core.zeroValue
import std.sync.{AtomicUInt32, AtomicBool}
import std.concurrent.tasksmacro.*

internal class TaskArray<T> <: Task<Array<T>> & Takes<Unit> {
    let tasksLeft: AtomicUInt32
    let failed = AtomicBool(false)
    let results: Array<T>

    TaskArray(arr: Array<Task<T>>, spawner: Spawner) {
        super(spawner)
        results = Array(arr.size, repeat: unsafe { zeroValue<T>() })
        tasksLeft = AtomicUInt32(UInt32(arr.size))
        this.initNativeResources()
        for (i in 0..arr.size) {
            arr[i].addFastContinuation(TaskArrayHook(this, i))
        }
    }

    public func next(_: Unit): ?TaskChainLink {
        let outcome = this.results
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

internal class TaskArrayHook<T> <: Takes<T> {
    TaskArrayHook(let wrapped: TaskArray<T>, let idx: Int64) {}

    public func next(t: T): ?TaskChainLink {
        this.wrapped.results[idx] = t
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

public func taskArray<T>(arr: Array<Task<T>>): Task<Array<T>> {
    if (arr.size==0) {
        return task {[]}
    }
    TaskArray(arr, arr[0].spawner)
}

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
    Tasks2(task1, task2, task1.spawner)
}
*/

// ====================
// Macro-generated tasks
// ====================

@GenerateTasksUpTo[16]
struct _GenerateTasks {}
