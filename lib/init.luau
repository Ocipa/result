local Result = require(script.Result)

export type SuccessResult<T> = Result.SuccessResult<T>
export type ErrorResult<T> = Result.ErrorResult<T>
export type PendingResult<T> = Result.PendingResult<T>

export type Result<T> = Result.Result<T>

return {
	success = Result.success,
	error = Result.error,
	try = Result.try,
	backToObject = Result.backToObject,
	is = Result.is,
}
