local lib = {
	has_failed = false,
	total_tests = 0,
	passed_tests = 0,
	failed_tests = 0,
}

function lib.test_case<T...>(name: string, fn: (T...) -> (), ...: T...)
	lib.total_tests += 1
	local success, err = (pcall :: any)(fn, ...)

	if success then
		lib.passed_tests += 1
		print(`  ✓ {name}`)
	else
		lib.failed_tests += 1
		lib.has_failed = true

		print(`  ✗ {name}`)
		print(`    Error: {err}`)
	end
end

function lib.reset_stats()
	lib.has_failed = false
	lib.total_tests = 0
	lib.passed_tests = 0
	lib.failed_tests = 0
end

return lib
