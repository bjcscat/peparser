local int64 = require("./int64")

type function get_type_from_field_value(field_value: type): type
	local read_fn = field_value:readproperty(types.singleton("read"))

	assert(read_fn and read_fn.tag == "function")

	return assert(read_fn:returns().head)[1]
end

type function make_table_from_union_type(inner: type): type
	local fields = if inner.tag == "union" then inner:components() else { inner }

	local new_fields = types.newtable()

	for _, field in fields do
		local ran = false

		for k, v in field:properties() do
			-- next doesnt work very well for types ig
			if ran then
				error("Struct field definitions must have exactly one key-value pair")
			end

			new_fields:setproperty(assert(k), get_type_from_field_value(v.read))
			ran = true
		end
	end

	return new_fields
end

export type FieldType<T> = {
	read __inner: T,

	read read: (buffer: buffer, offset: number) -> (T, number),
	read write: (buffer: buffer, offset: number, value: T) -> number,
	read size: number,
}

local function make_numeric_field_type(size: number, signed: boolean): FieldType<number>
	local reader: (buffer, number) -> number
	local writer: (buffer, number, number) -> ()

	if size == 1 then
		reader = if signed then buffer.readi8 else buffer.readu8
		writer = if signed then buffer.writei8 else buffer.writeu8
	elseif size == 2 then
		reader = if signed then buffer.readi16 else buffer.readu16
		writer = if signed then buffer.writei16 else buffer.writeu16
	elseif size == 4 then
		reader = if signed then buffer.readi32 else buffer.readu32
		writer = if signed then buffer.writei32 else buffer.writeu32
	else
		error("Unsupported numeric field size: " .. tostring(size))
	end

	local field_type: FieldType<number> = {
		__inner = nil :: never,

		read = function(buffer: buffer, offset: number): (number, number)
			local value = reader(buffer, offset)

			return value, offset + size
		end,
		write = function(buffer: buffer, offset: number, value: number): number
			writer(buffer, offset, value)

			return offset + size
		end,
		size = size,
	}

	return field_type
end

local u64_field: FieldType<vector> = {
	__inner = nil :: never,

	read = function(buffer: buffer, offset: number): (vector, number)
		local value = int64.from_buffer(buffer, offset)
		return value, offset + 8
	end,
	write = function(buffer: buffer, offset: number, value: vector): number
		int64.write_to_buffer(buffer, value, offset)
		return offset + 8
	end,
	size = 8,
}

local function array<T>(field_type: FieldType<T>, size: number): FieldType<{ T }>
	return {
		__inner = nil :: never,

		read = function(buffer: buffer, offset: number): ({ T }, number)
			local target = table.create(size)

			for i = 1, size do
				local value: T
				value, offset = field_type.read(buffer, offset)
				target[i] = value
			end

			return target, offset
		end,

		write = function(buffer: buffer, offset: number, value: { T }): number
			for i = 1, size do
				offset = field_type.write(buffer, offset, value[i])
			end

			return offset
		end,

		size = field_type.size * size,
	}
end

local function null_terminated_string(size: number): FieldType<string>
	return {
		__inner = nil :: never,

		read = function(b: buffer, offset: number): (string, number)
			local real_size = size
			for i = 0, size - 1 do
				local byte = buffer.readu8(b, offset + i)

				if byte == 0 then
					real_size = i
					break
				end
			end

			local value = buffer.readstring(b, offset, real_size)

			return value, offset + size
		end,

		write = function(b: buffer, offset: number, value: string): number
			assert(#value <= size)

			buffer.writestring(b, offset, value)
			return offset + size
		end,

		size = size,
	}
end

local function struct<T>(fields: { T }): FieldType<make_table_from_union_type<T>>
	for _, field: { [string]: FieldType<unknown> } in fields do
		local field_name, field_type = next(field)

		assert(
			(field_name ~= nil and field_type ~= nil) and next(field, field_name) == nil,
			"Struct field definitions must have exactly one key-value pair"
		)
	end

	local function read(buffer: buffer, offset: number): (T, number)
		local result: T & { [string]: unknown } = {}

		for _, field in fields do
			local field_name: string?, field_type: FieldType<unknown>? = next(field :: any)

			assert(
				(field_name ~= nil and field_type ~= nil) and next(field, field_name) == nil,
				"Struct field definitions must have exactly one key-value pair"
			)

			local value: unknown
			value, offset = field_type.read(buffer, offset)
			result[field_name] = value
		end

		return result, offset
	end

	local function write(buffer: buffer, offset: number, value: T): number
		for _, field in fields do
			local field_name: string?, field_type: FieldType<T>? = next(field :: any)

			assert(
				(field_name ~= nil and field_type ~= nil) and next(field, field_name) == nil,
				"Struct field definitions must have exactly one key-value pair"
			)

			offset = field_type.write(buffer, offset, (value :: { [string]: unknown })[field_name])
		end

		return offset
	end

	local total_size = 0
	for _, field in fields do
		local _, field_type = next(field)
		total_size = total_size + (field_type :: FieldType<unknown>).size
	end

	return {
		__inner = nil :: never,

		read = read,
		write = write,
		size = total_size,
	} :: FieldType<make_table_from_union_type<T>>
end

return {
	i8 = make_numeric_field_type(1, true),
	u8 = make_numeric_field_type(1, false),
	i16 = make_numeric_field_type(2, true),
	u16 = make_numeric_field_type(2, false),
	i32 = make_numeric_field_type(4, true),
	u32 = make_numeric_field_type(4, false),
	u64 = u64_field,

	array = array,
	struct = struct,
	null_terminated_string = null_terminated_string,

	int64_lib = int64,
}
