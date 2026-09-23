-- The harness itself: the cooperative scheduler and the fake DataStore's concurrency model.
-- Persistence tests lean on both, so they are pinned down here first.

describe("scheduler: task.spawn and task.wait", function()
	it("runs a spawned thread immediately, up to its first yield", function()
		local trace = {}
		task.spawn(function()
			table.insert(trace, "before")
			task.wait(1)
			table.insert(trace, "after")
		end)
		expect(table.concat(trace, ",")).toBe("before")
		expect(Harness.pendingThreads()).toBe(1)
	end)

	it("resumes a waiting thread only once its time arrives", function()
		local woke = false
		Harness.setClock(0)
		task.spawn(function()
			task.wait(2)
			woke = true
		end)
		Harness.advance(1.9)
		expect(woke).toBe(false)
		Harness.advance(0.2)
		expect(woke).toBe(true)
	end)

	it("wakes threads in time order, then in the order they were scheduled", function()
		local order = {}
		Harness.setClock(0)
		for _, spec in { { "c", 3 }, { "a", 1 }, { "b1", 2 }, { "b2", 2 } } do
			task.spawn(function()
				task.wait(spec[2])
				table.insert(order, spec[1])
			end)
		end
		Harness.settle()
		expect(table.concat(order, ",")).toBe("a,b1,b2,c")
	end)

	it("interleaves threads that alternate yields", function()
		local trace = {}
		Harness.setClock(0)
		for _, name in { "x", "y" } do
			task.spawn(function()
				for step = 1, 3 do
					table.insert(trace, name .. step)
					task.wait(1)
				end
			end)
		end
		Harness.settle()
		expect(table.concat(trace, ",")).toBe("x1,y1,x2,y2,x3,y3")
	end)

	it("lets time pass on the main thread and runs what falls due meanwhile", function()
		local woke = false
		Harness.setClock(10)
		task.spawn(function()
			task.wait(1)
			woke = true
		end)
		local elapsed = task.wait(5) -- main test thread: cannot yield, so time passes instead
		expect(woke).toBe(true)
		expect(elapsed).toBeCloseTo(5, 1e-9)
		expect(Harness.now()).toBeCloseTo(15, 1e-9)
	end)

	it("returns the time actually slept", function()
		local slept
		Harness.setClock(0)
		task.spawn(function()
			slept = task.wait(0.75)
		end)
		Harness.settle()
		expect(slept).toBeCloseTo(0.75, 1e-9)
	end)
end)

describe("scheduler: delay, defer, cancel and errors", function()
	it("runs a delayed function after its delay", function()
		local ran = false
		Harness.setClock(0)
		task.delay(3, function()
			ran = true
		end)
		Harness.advance(2)
		expect(ran).toBe(false)
		Harness.advance(1)
		expect(ran).toBe(true)
	end)

	it("runs a deferred function at the next resumption point, not inline", function()
		local ran = false
		task.defer(function()
			ran = true
		end)
		expect(ran).toBe(false)
		Harness.advance(0)
		expect(ran).toBe(true)
	end)

	it("cancels a waiting thread", function()
		local woke = false
		local thread = task.spawn(function()
			task.wait(1)
			woke = true
		end)
		task.cancel(thread)
		Harness.settle()
		expect(woke).toBe(false)
		expect(Harness.pendingThreads()).toBe(0)
	end)

	it("records an error raised inside a spawned thread", function()
		task.spawn(function()
			task.wait(1)
			error("boom in background", 0)
		end)
		Harness.settle()
		local errors = Harness.takeTaskErrors() -- taken here, so this test does not fail on it
		expect(#errors).toBe(1)
		expect(errors[1]).toBe("boom in background")
	end)

	it("starts every test with an empty queue", function()
		expect(Harness.pendingThreads()).toBe(0)
	end)
end)

describe("fake DataStore concurrency", function()
	it("stays synchronous with zero latency", function()
		local store = __FakeDataStore.new()
		store:UpdateAsync("k", function()
			return { n = 1 }
		end)
		expect(store.writes).toBe(1)
		expect(Harness.pendingThreads()).toBe(0)
	end)

	it("keeps a write in flight for its latency", function()
		local store = __FakeDataStore.new()
		store.writeLatency = 2
		Harness.setClock(0)
		task.spawn(function()
			store:UpdateAsync("k", function()
				return { n = 1 }
			end)
		end)
		expect(store.writes).toBe(0)
		expect(store.inFlight.k).toBe(1)
		Harness.settle()
		expect(store.writes).toBe(1)
		expect(store.inFlight.k).toBe(0)
	end)

	it("freezes the value at the moment the transform returns", function()
		local store = __FakeDataStore.new()
		store.writeLatency = 1
		local live = { n = 1 }
		task.spawn(function()
			store:UpdateAsync("k", function()
				return live
			end)
		end)
		live.n = 99 -- changed after the transform returned, while the write is in flight
		Harness.settle()
		expect(store:Peek("k").n).toBe(1)
	end)

	it("re-runs a transform when another write commits first", function()
		local store = __FakeDataStore.new()
		store.writeLatency = 1
		local function increment(stored)
			local value = stored or { n = 0 }
			value.n += 1
			return value
		end
		task.spawn(function()
			store:UpdateAsync("k", increment)
		end)
		task.spawn(function()
			store:UpdateAsync("k", increment)
		end)
		expect(store.peakInFlight.k).toBe(2)
		Harness.settle()
		-- Neither increment is lost: the loser re-read the winner's value and applied on top.
		expect(store:Peek("k").n).toBe(2)
		expect(store.transformReruns).toBe(1)
	end)
end)
