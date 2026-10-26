--!strict
-- Assertions for specs; each raises an error describing the mismatch.

local Assert = {}

function Assert.equal<T>(actual: T, expected: T, message: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				if message then message .. ": " else "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function Assert.near(actual: number, expected: number, tolerance: number?, message: string?)
	if math.abs(actual - expected) > (tolerance or 1e-6) then
		error(
			string.format(
				"%sexpected %s, got %s",
				if message then message .. ": " else "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function Assert.truthy(value: any, message: string?)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

function Assert.falsy(value: any, message: string?)
	if value then
		error(message or "expected a falsy value", 2)
	end
end

-- Returns the first event of `kind` in `events`, or nil.
function Assert.findEvent(events: { any }, kind: string): any
	for _, event in events do
		if event.kind == kind then
			return event
		end
	end
	return nil
end

return Assert
