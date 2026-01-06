-- aetherkrnl v2.2-fixed-finally
local obfuscator_state = {
	var_counter = 0,
	func_counter = 0,
	table_counter = 0,
	closure_counter = 0,
	vm_counter = 0
}

local keyword_list = {
	"and", "break", "do", "else", "elseif", "end", "false", "for",
	"function", "if", "in", "local", "nil", "not", "or", "repeat",
	"return", "then", "true", "until", "while", "continue"
}

local keywords = {}
for _, k in ipairs(keyword_list) do
	keywords[k] = true
end

function next_var()
	obfuscator_state.var_counter = obfuscator_state.var_counter + 1
	return string.format("VAR_%02d", obfuscator_state.var_counter)
end

function next_func()
	obfuscator_state.func_counter = obfuscator_state.func_counter + 1
	return string.format("FUNC_%02d", obfuscator_state.func_counter)
end

function next_table()
	obfuscator_state.table_counter = obfuscator_state.table_counter + 1
	return string.format("TABLE_%02d", obfuscator_state.table_counter)
end

function next_closure()
	obfuscator_state.closure_counter = obfuscator_state.closure_counter + 1
	return string.format("QVM_CLOSURE%02d", obfuscator_state.closure_counter)
end

function next_vm_name()
	obfuscator_state.vm_counter = obfuscator_state.vm_counter + 1
	return string.format("QUARTERVM_%02d", obfuscator_state.vm_counter)
end

function encrypt_payload(src)
	local key = math.random(1, 255)
	local enc = {}
	local len = string.len(src)
	
	for i = 1, len do
		local byte = string.byte(src, i)
		local corrupted = bit32.bxor(byte, key)
		corrupted = bit32.band(bit32.lrotate(corrupted, i % 8), 255)
		corrupted = bit32.band(corrupted + (i % 256), 255)
		enc[i] = string.char(corrupted)
	end
	
	return table.concat(enc), key
end

function escape_data(data)
	local esc = {}
	local pos = 1
	for i = 1, #data do
		esc[pos] = string.format("%03d", string.byte(data, i))
		pos = pos + 1
	end
	return table.concat(esc)
end

function is_alnum(ch)
	return ch:match("[%a%d_]")
end

function is_alpha(ch)
	return ch:match("[%a_]")
end

function is_digit(ch)
	return ch:match("[%d]")
end

function strip_comments(src)
	local result = {}
	local i = 1
	local len = #src
	
	while i <= len do
		local ch = src:sub(i, i)
		
		if ch == "-" and src:sub(i + 1, i + 1) == "-" then
			if src:sub(i + 2, i + 3) == "[[" then
				local close = "]]"
				local pos = i + 4
				while pos <= len - 1 do
					if src:sub(pos, pos + 1) == close then
						i = pos + 2
						break
					end
					pos = pos + 1
				end
				if pos > len - 1 then
					i = len + 1
				end
			else
				while i <= len and src:sub(i, i) ~= "\n" do
					i = i + 1
				end
			end
		else
			result[#result + 1] = ch
			i = i + 1
		end
	end
	
	return table.concat(result)
end

function tokenize(src)
	local tokens = {}
	local i = 1
	local len = #src
	
	while i <= len do
		local ch = src:sub(i, i)
		
		if ch:match("%s") then
			while i <= len and src:sub(i, i):match("%s") do
				tokens[#tokens + 1] = {type = "whitespace", value = src:sub(i, i)}
				i = i + 1
			end
		elseif ch == '"' or ch == "'" then
			local start = i
			local delim = ch
			i = i + 1
			while i <= len do
				if src:sub(i, i) == "\\" then
					i = i + 2
				elseif src:sub(i, i) == delim then
					i = i + 1
					break
				else
					i = i + 1
				end
			end
			tokens[#tokens + 1] = {type = "string", value = src:sub(start, i - 1)}
		elseif is_digit(ch) then
			local start = i
			while i <= len and (is_digit(src:sub(i, i)) or src:sub(i, i) == ".") do
				i = i + 1
			end
			tokens[#tokens + 1] = {type = "number", value = src:sub(start, i - 1)}
		elseif is_alpha(ch) then
			local start = i
			while i <= len and is_alnum(src:sub(i, i)) do
				i = i + 1
			end
			local word = src:sub(start, i - 1)
			if keywords[word] then
				tokens[#tokens + 1] = {type = "keyword", value = word}
			else
				tokens[#tokens + 1] = {type = "identifier", value = word}
			end
		else
			tokens[#tokens + 1] = {type = "symbol", value = ch}
			i = i + 1
		end
	end
	
	return tokens
end

function extract_closures(src)
	local closure_map = {}
	local closures = {}
	local tokens = tokenize(src)
	local depth = 0
	local closure_stack = {}
	local result_tokens = {}
	
	local i = 1
	while i <= #tokens do
		local token = tokens[i]
		
		if token.type == "keyword" and token.value == "function" then
			if depth == 0 then
				closure_stack[#closure_stack + 1] = i
			end
			depth = depth + 1
			result_tokens[#result_tokens + 1] = token
		elseif token.type == "keyword" and token.value == "end" and depth > 0 then
			depth = depth - 1
			result_tokens[#result_tokens + 1] = token
			
			if depth == 0 and #closure_stack > 0 then
				local start_idx = closure_stack[#closure_stack]
				closure_stack[#closure_stack] = nil
				local closure_tokens = {}
				
				for j = start_idx, i do
					closure_tokens[#closure_tokens + 1] = tokens[j].value
				end
				
				local closure_src = table.concat(closure_tokens)
				local name = next_closure()
				closures[#closures + 1] = {name = name, src = closure_src}
				closure_map[closure_src] = name
				
				result_tokens[#result_tokens] = {type = "identifier", value = name}
			end
		else
			result_tokens[#result_tokens + 1] = token
		end
		
		i = i + 1
	end
	
	local result = {}
	for _, t in ipairs(result_tokens) do
		result[#result + 1] = t.value
	end
	
	return table.concat(result), closures
end

function rename_identifiers(src)
	local tokens = tokenize(src)
	local mapping = {}
	local result = {}
	
	for _, token in ipairs(tokens) do
		if token.type == "identifier" then
			if not mapping[token.value] then
				if token.value:find("^[A-Z]") then
					mapping[token.value] = next_func()
				elseif token.value:sub(1, 1) == "_" or token.value:find("^l_") then
					mapping[token.value] = next_table()
				else
					mapping[token.value] = next_var()
				end
			end
			result[#result + 1] = mapping[token.value]
		else
			result[#result + 1] = token.value
		end
	end
	
	return table.concat(result)
end

function generate_quartervm(enc_data, enc_key, closures)
	local vm_name = next_vm_name()
	local closure_defs = ""
	
	if #closures > 0 then
		local defs = {}
		for i, closure in ipairs(closures) do
			defs[#defs + 1] = string.format("QVM_CLOSURE%02d = [[%s]]", i, closure.src)
		end
		closure_defs = "local " .. table.concat(defs, ", ") .. ";"
	end
	
	return string.format([[(function()
	local DECRYPT_KEY = %d
	local PAYLOAD_DATA = "%s"
	%s
	
	local function DECRYPT_BYTE(byte, idx)
		local val = byte
		val = bit32.band(val - (idx %% 256), 255)
		val = bit32.band(bit32.rrotate(val, idx %% 8), 255)
		val = bit32.bxor(val, DECRYPT_KEY)
		return string.char(val)
	end
	
	local function UNPACK_PAYLOAD()
		local len = #PAYLOAD_DATA / 3
		local out = {}
		local pos = 1
		
		for i = 1, len do
			local code = tonumber(PAYLOAD_DATA:sub(pos, pos + 2))
			out[i] = DECRYPT_BYTE(code, i)
			pos = pos + 3
		end
		
		return table.concat(out)
	end
	
	local function EXECUTE_CODE(src)
		local f, err = loadstring(src)
		if not f then
			error(string.format("quartervm execution failed: %%s", err))
		end
		return f()
	end
	
	local function MAIN()
		local decrypted = UNPACK_PAYLOAD()
		return EXECUTE_CODE(decrypted)
	end
	
	return MAIN()
end)()]], enc_key, enc_data, closure_defs)
end

function aetherkrnl_obfuscate(src)
	if type(src) ~= "string" then
		error(string.format("aetherkrnl: expected string, got %s", type(src)))
	end
	
	if src == "" then
		error("aetherkrnl: source cannot be empty")
	end
	
	obfuscator_state.var_counter = 0
	obfuscator_state.func_counter = 0
	obfuscator_state.table_counter = 0
	obfuscator_state.closure_counter = 0
	obfuscator_state.vm_counter = 0
	
	src = strip_comments(src)
	src, closures = extract_closures(src)
	src = rename_identifiers(src)
	
	local enc_data, enc_key = encrypt_payload(src)
	local esc_data = escape_data(enc_data)
	
	return generate_quartervm(esc_data, enc_key, closures)
end

return {
	obfuscate = aetherkrnl_obfuscate,
	version = "2.2-aetherkrnl-fixed-finally",
	quartervm = true,
	modules = {
		tokenizer = tokenize,
		extractor = extract_closures,
		renamer = rename_identifiers
	}
}
