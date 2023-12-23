-- NOTE: at the time of writing this, luau doens't support function unions.
-- When attempting to call a function union, it says "cannot call non function",
-- and the only workaround I could find is to define the function type outside\
-- of the union.
type after<T> = (self: Result<T>, callback: (result: Result<T>) -> nil) -> Result<T>

type SuccessImpl<T> = {
	unwrap: (self: Result<T>) -> T,
	after: after<T>,
}

export type SuccessResult<T> = typeof(setmetatable(
	{} :: { Type: "Success", Result: T },
	{} :: { __index: SuccessImpl<T>, __tostring: (SuccessResult<T>) -> string }
))

type ErrorImpl<T> = {
	unwrap: (self: Result<T>) -> nil,
	retry: (self: Result<T>) -> Result<T>,
	after: after<T>,
}

export type ErrorResult<T> = typeof(setmetatable(
	{} :: { Type: "Error", Error: string },
	{} :: { __index: ErrorImpl<T>, __tostring: (ErrorResult<T>) -> string }
))

type PendingImpl<T> = {
	cancel: (self: Result<T>) -> (),
	await: (self: Result<T>) -> SuccessResult<T> | ErrorResult<T>,
	after: after<T>,
}

export type PendingResult<T> = typeof(setmetatable(
	{} :: { Type: "Pending", Thread: thread },
	{} :: { __index: PendingImpl<T>, __tostring: (PendingResult<T>) -> string }
))

type ResultImpl<T> = SuccessImpl<T> & ErrorImpl<T> & PendingImpl<T>
export type Result<T> = SuccessResult<T> | ErrorResult<T> | PendingResult<T>

--[=[
    @class Result
    @__index module
]=]
local module: ResultImpl<any> = {} :: ResultImpl<any>

function module:unwrap()
	if self.Type == "Error" then
		error(self.Error)
	elseif self.Type == "Success" then
		return self.Result
	end

	return nil
end

--[=[
	@errors
]=]
function module:retry()
	local result = self :: any

	if result.Type == "Error" then
		if not result._callback then
			error(
				"Result did not have a callback, the primary cause of this is\n"
					.. "the result being constructed with Result.error(), try using\n"
					.. "Result.try()"
			)
		end

		result.Type = "Pending"
		result.Error = nil

		local thread = task.spawn(function()
			local success, err = pcall(result._callback)

			if success then
				result.Type = "Success"
				result.Result = err
			else
				result.Type = "Error"
				result.Error = err
			end

			for _, v in result._afterCallbacks do
				task.spawn(v, result)
			end

			if success then
				table.clear(result._afterCallbacks)
			end
		end)
		result.Thread = thread
	end

	return result
end

function module:cancel()
	if self.Type == "Pending" then
		if coroutine.status(self.Thread) == "dead" then
			return
		end

		task.cancel(self.Thread)
	end
end

function module:await()
	-- TODO: make sure this gets handled correctly if result:cancel()
	while self.Type == "Pending" do
		task.wait()
	end

	return self :: any
end

function module:after(callback)
	if self.Type ~= "Pending" then
		task.spawn(callback, self)
	else
		table.insert((self :: any)._afterCallbacks, callback)
	end

	return self
end

local mt = {
	__index = module,
	__tostring = function(result)
		local returnType = "<unknown>"

		if result.Type == "Success" then
			returnType = `<{typeof(result.Result)}>`
		elseif result.Type == "Error" then
			returnType = ` Error: {result.Error}`
		end

		return `{result.Type}Result{returnType}`
	end,
}

local constructors
constructors = {
	success = function<T>(value: T): SuccessResult<T>
		local self = {
			Type = "Success",
			Result = value,
		}

		return setmetatable(self, mt) :: any
	end,

	error = function(errorMessage: string?): ErrorResult<never>
		local self = {
			Type = "Error",
			Error = errorMessage or "",
		}

		return setmetatable(self, mt) :: any
	end,

	try = function<T>(callback: () -> T): PendingResult<T>
		local self = {
			Type = "Pending",

			_callback = callback,
			_afterCallbacks = {},
		} :: any

		local thread = task.spawn(function()
			local success, err = pcall(callback)

			self.Thread = nil

			if success then
				self.Type = "Success"
				self.Result = err
			else
				self.Type = "Error"
				self.Error = err
			end

			for _, v in self._afterCallbacks do
				task.spawn(v, self)
			end

			if success then
				table.clear(self._afterCallbacks)
			end
		end)
		self.Thread = thread

		return setmetatable(self, mt)
	end,

	backToObject = function<T>(self: Result<T>): Result<T>
		return setmetatable(self :: any, mt) :: any
	end,

	is = function(value: unknown): boolean
		if typeof(value ~= "table") then
			return false
		end

		return getmetatable(value :: any) == mt
	end,
}

return constructors
