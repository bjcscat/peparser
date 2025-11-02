local base64 = require("./utils/base64")
local test_case = require("./utils/test_case")

local test_data = (require)("../test_info")

local exe_contents = base64.decode(buffer.fromstring(test_data.contents))

local total_suites = 0
local passed_suites = 0
local failed_suites = 0
local total_cases = 0
local passed_cases = 0
local failed_cases = 0

for _, test_name in test_data.test_names do
	test_case.reset_stats()
	total_suites += 1

	print(`[{test_name}]`)

	local success, result = pcall(function()
		return (require)(`./{test_name}.test`)(exe_contents)
	end)

	if not success then
		-- Test suite errored
		print(`  ✗ Suite errored: {result}`)
		failed_suites += 1
	elseif result then
		print(`  → Passed ({test_case.passed_tests}/{test_case.total_tests} cases)`)
		passed_suites += 1
		total_cases += test_case.total_tests
		passed_cases += test_case.passed_tests
	else
		print(`  → Failed ({test_case.failed_tests}/{test_case.total_tests} cases failed)`)
		failed_suites += 1
		total_cases += test_case.total_tests
		passed_cases += test_case.passed_tests
		failed_cases += test_case.failed_tests
	end
	print("")
end

print(string.rep("=", 50))
print(`Test Summary:`)
print(`  Suites: {passed_suites}/{total_suites} passed`)
print(`  Cases:  {passed_cases}/{total_cases} passed`)
if failed_suites > 0 then
	print(`  Failed: {failed_suites} suite(s), {failed_cases} case(s)`)
	error("Test failures detected")
end
