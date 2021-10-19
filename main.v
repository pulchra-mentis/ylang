import os
import pcre
import regex
import strings

fn main() {
	mut base_directory := "."
	if os.args.len >= 2 {
		base_directory = os.args[1]
	}

	y_files := os.walk_ext(base_directory, '.y')

	generated_file_name := 'app.v'
	// create empty file
	if os.exists(generated_file_name) {
		//panic('generated file already exists')
	}
	mut f := os.create(generated_file_name) or { panic(err) }
	f.close()

	// iterate over all the y_files
	for y_file in y_files {
		transpile_y_file(y_file, generated_file_name)
	}
}

fn transpile_y_file(y_file string, out_file string) {
	println(y_file)
	y_file_contents := os.read_file(y_file) or { panic(err) }
	println('')
	
	r := pcre.new_regex(r'#(.|\n)+?\n\s*\([^#]+\)', 0) or { panic(err) }

	mut file_index := 0
	for {
		trimmed_file_contents := y_file_contents[file_index..]
		matches := r.match_str(trimmed_file_contents, 0, 0) or { return }

		declaration := matches.get(0) or { break }
		file_index += trimmed_file_contents.index(declaration) or { panic(err) } + declaration.len

		transpile_y_declaration(declaration, out_file)
	}

	r.free()
}

fn transpile_y_declaration(y_declaration string, out_file string) {
	println('transpiling: $y_declaration')

	token_stream := tokenize_y_declaration(y_declaration)
	root_node, _ := parse_y_declaration(token_stream)
	code := transpile_ast(root_node)
	println(code)

	println('finished transpiling\n')
}

fn transpile_ast(root_node YFunctionDeclarationNode) string {
	mut sb := strings.new_builder(1024)

	is_main := transpile_header(root_node, mut sb)
	transpile_body(root_node.body, mut sb, is_main)
	sb.write_string('\n}\n\n')
	
	return sb.str()
}

fn transpile_body(body YFunctionBodyDeclarationNode, mut sb strings.Builder, is_main bool) {
	if !is_main {
		sb.write_string('return ')
	}
	transpile_expression(body.expression, mut sb)
}

fn transpile_expression(expression YExpression, mut sb strings.Builder) {
	if expression.kind == .fn_call {
		transpile_fn_call(expression.fn_call, mut sb)
	} else {
		transpile_literal(expression.literal, mut sb)
	}
}

fn transpile_fn_call(fn_call YFunctionCallNode, mut sb strings.Builder) {
	sb.write_string('${fn_call.fn_name}(')
	mut count := 0
	for count < fn_call.arguments.len {
		transpile_expression(fn_call.arguments[count], mut sb)

		if count+1 < fn_call.arguments.len {
			sb.write_string(', ')
		}
		count ++
	}
	sb.write_string(')')
}

fn transpile_literal(literal YLiteral, mut sb strings.Builder) {
	sb.write_string(literal.token.text)
}

fn transpile_header(root_node YFunctionDeclarationNode, mut sb strings.Builder) bool {
	sb.write_string('fn ')

	is_main := root_node.header.fn_type == 'app'

	if is_main {
		sb.write_string('main')
	}else{
		sb.write_string(root_node.header.fn_name)
	}
	sb.write_string('(')

	params := root_node.parameter_list.parameters
		.map('$it.par_name ${translate_type(it.par_type)}')
	sb.write_string(params.join(', '))

	sb.write_string(')')

	if !is_main {
		sb.write_string(' ')
		sb.write_string(translate_type(root_node.header.fn_type))
	}

	sb.write_string(' {\n')
	return is_main
}

fn translate_type(type_name string) string {
	return match type_name {
		'int' { 'int' }
		'str' { 'string' }
		'dbl' { 'f64' }
		'bol' { 'bool' }
		else { panic('cannot translate unknown type "$type_name"') }
	}
}

struct YFunctionDeclarationNode {
	header YFunctionHeaderDeclarationNode
	parameter_list YFunctionParameterDeclarationListNode
	body YFunctionBodyDeclarationNode
}

struct YFunctionHeaderDeclarationNode {
	fn_name string
	fn_type string
}

struct YFunctionParameterDeclarationListNode {
	parameters []YFunctionParameterDeclarationNode
}

struct YFunctionParameterDeclarationNode {
	par_name string
	par_type string
}

struct YFunctionBodyDeclarationNode {
	expression YExpression
}

enum YExpressionKind {
	literal
	fn_call
}

struct YExpression {
mut:
	kind YExpressionKind
	fn_call YFunctionCallNode
	literal YLiteral
}

struct YFunctionCallNode {
	fn_name string
	arguments []YExpression
}

struct YLiteral {
	token YToken
}

fn parse_y_declaration(token_stream []YToken) (YFunctionDeclarationNode, int) {
	mut consumed := 0

	header, consumed_header := parse_y_function_header(token_stream)
	consumed += consumed_header

	parameter_list, consumed_param_list := parse_y_function_parameter_list(token_stream[consumed..])
	consumed += consumed_param_list

	for token_stream[consumed].kind == .doc_comment {
		consumed++
	}

	body, consumed_body := parse_y_function_body(token_stream[consumed..].reverse())
	consumed += consumed_body

	return YFunctionDeclarationNode {
		header: header
		parameter_list: parameter_list
		body: body
	}, consumed
}

fn parse_y_function_header(token_stream []YToken) (YFunctionHeaderDeclarationNode, int) {
	mut consumed := 0

	ensure_token(token_stream[consumed], .doc_identifier)
	fn_name := extract_doc_name_or_type(token_stream[consumed].text[1..])
	consumed++

	ensure_token(token_stream[consumed], .doc_colon)
	consumed++

	ensure_token(token_stream[consumed], .doc_type)
	fn_type := extract_doc_name_or_type(token_stream[consumed].text)
	consumed++

	ensure_token(token_stream[consumed], .doc_double_dash_comment)
	consumed++
	
	return YFunctionHeaderDeclarationNode{
		fn_name: fn_name
		fn_type: fn_type
	}, consumed
}

fn parse_y_function_parameter_list(token_stream []YToken) (YFunctionParameterDeclarationListNode, int) {
	mut consumed := 0
	mut parameters := []YFunctionParameterDeclarationNode{}

	for token_stream[consumed].kind == .doc_identifier {
		par_name := extract_doc_name_or_type(token_stream[consumed].text)
		consumed++

		ensure_token(token_stream[consumed], .doc_colon)
		consumed++

		ensure_token(token_stream[consumed], .doc_type)
		par_type := extract_doc_name_or_type(token_stream[consumed].text)
		consumed++

		ensure_token(token_stream[consumed], .doc_double_dash_comment)
		consumed++

		parameters << YFunctionParameterDeclarationNode {
			par_name: par_name
			par_type: par_type
		}
	}

	return YFunctionParameterDeclarationListNode {
		parameters: parameters
	}, consumed
}

fn parse_y_function_body(token_stream []YToken) (YFunctionBodyDeclarationNode, int) {
	mut consumed := 0

	expression, expression_consumed := parse_y_expression(token_stream)
	consumed += expression_consumed

	return YFunctionBodyDeclarationNode {
		expression: expression
	}, consumed
}

fn parse_y_expression(token_stream []YToken) (YExpression, int) {
	mut consumed := 0

	mut expression := YExpression{
	}

	if token_stream[consumed].kind == .par_open {
		fn_call, fn_call_consumed := parse_y_function_call(token_stream[consumed..])
		consumed += fn_call_consumed

		expression.kind = .fn_call
		expression.fn_call = fn_call
	} else {
		literal, literal_consumed := parse_y_literal(token_stream[consumed..])
		consumed += literal_consumed

		expression.kind = .literal
		expression.literal = literal
	}

	return expression, consumed
}

fn parse_y_function_call(token_stream []YToken) (YFunctionCallNode, int) {
	mut consumed := 0

	ensure_token(token_stream[consumed], .par_open)
	consumed++

	ensure_token(token_stream[consumed], .identifier)
	fn_name := token_stream[consumed].text
	consumed++

	mut arguments := []YExpression{}
	for token_stream[consumed].kind != .par_close {
		argument, argument_consumed := parse_y_expression(token_stream[consumed..])
		arguments << argument
		consumed += argument_consumed
	}

	ensure_token(token_stream[consumed], .par_close)
	consumed++

	return YFunctionCallNode {
		fn_name: fn_name
		arguments: arguments
	}, consumed
}

fn parse_y_literal(token_stream []YToken) (YLiteral, int) {
	is_literal := match token_stream[0].kind {
		.int_literal,  .double_literal, .string_literal, .bool_literal, .identifier { true }
		else { false }
	}

	if !is_literal {
		panic('expected literal token but got ${token_stream[0]}')
	}

	return YLiteral {
		token: token_stream[0]
	}, 1
}

fn ensure_token(token YToken, kind YTokenKind) {
	if token.kind != kind {
		panic('unexpected token kind ${token.kind}, expected $kind')
	}
}

fn extract_doc_name_or_type(raw string) string {
	return raw.trim('#').trim(' ').trim('`').trim('`')
}

enum YTokenKind {
	undefined

	doc_identifier
	doc_type
	doc_colon
	doc_double_dash_comment
	doc_comment

	par_open
	par_close

	identifier
	
	int_literal
	double_literal
	string_literal
	bool_literal

	white_space
	end_of_file
}

struct YToken {
	kind YTokenKind
	text string
	skip bool
}

fn tokenize_y_declaration(y_declaration string) []YToken {
	tokenizer_functions := [
		tokenize_doc_identifier,
		tokenize_doc_type,
		tokenize_doc_colon,
		tokenize_doc_double_dash_comment,
		tokenize_doc_comment,

		tokenize_par_close,
		tokenize_par_open,

		tokenize_identifier,

		tokenize_int_literal,
		tokenize_double_literal,
		tokenize_string_literal,
		tokenize_bool_literal,

		tokenize_white_space,
		tokenize_new_line
	]

	mut token_stream := []YToken{}

	mut current_index := 0
	for current_index < y_declaration.len {
		mut tokenized := false

		for tokenizer_function in tokenizer_functions {
			if token := tokenizer_function(y_declaration[current_index..]) {
				current_index += token.text.len

				if !token.skip {
					token_stream << token
				}

				tokenized = true
				break
			}
		}

		if !tokenized {
			panic('tokenization failed at index $current_index for: \'${y_declaration[current_index..]}\'')
		}
	}

	return token_stream
}

fn tokenize_pattern(input string, pattern string, kind YTokenKind, skip bool) ?YToken {
	mut re := regex.regex_opt('^$pattern') or { panic(err) }
	re.flag = regex.f_nl
	start, end := re.match_string(input)

	if start >= 0 {
		return YToken{
			kind: kind
			text: input[start..end]
			skip: skip
		}
	}

	return none
}

fn tokenize_doc_identifier(input string) ?YToken {
	return tokenize_pattern(input, r'# +`(\w|_)+`', .doc_identifier, false)
}

fn tokenize_doc_type(input string) ?YToken {
	return tokenize_pattern(input, r'`(\w|_)+`', .doc_type, false)
}

fn tokenize_doc_colon(input string) ?YToken {
	return tokenize_pattern(input, r':', .doc_colon, false)
}

fn tokenize_doc_double_dash_comment(input string) ?YToken {
	return tokenize_pattern(input, r'--.*', .doc_double_dash_comment, false)
}

fn tokenize_doc_comment(input string) ?YToken {
	return tokenize_pattern(input, r'# .+', .doc_comment, false)
}

fn tokenize_par_close(input string) ?YToken {
	return tokenize_pattern(input, r'\(', .par_close, false)
}

fn tokenize_par_open(input string) ?YToken {
	return tokenize_pattern(input, r'\)', .par_open, false)
}

fn tokenize_identifier(input string) ?YToken {
	return tokenize_pattern(input, r'[a-zA-Z_]+', .identifier, false)
}

fn tokenize_white_space(input string) ?YToken {
	return tokenize_pattern(input, r'\s', .white_space, true)
}
	
fn tokenize_new_line(input string) ?YToken {
	mut re := regex.regex_opt('\n') or { panic(err) }
	start, _ := re.match_string(input)

	if start >= 0 {
		return YToken{
			kind: .white_space
			text: "\n"
			skip: true
		}
	}

	return none
}

fn tokenize_int_literal(input string) ?YToken {
	return tokenize_pattern(input, r'\d+', .int_literal, false)
}

fn tokenize_double_literal(input string) ?YToken {
	return tokenize_pattern(input, r'(\d+\.\d+)|(\.\d+)|(\d+\.)', .double_literal, false)
}

fn tokenize_string_literal(input string) ?YToken {
	return tokenize_pattern(input, r'"(.)*"', .string_literal, false)
}

fn tokenize_bool_literal(input string) ?YToken {
	return tokenize_pattern(input, r'(tru)|(fls)', .bool_literal, false)
}