import os
import pcre
import regex

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
	println(token_stream)

	// tokenize declaration
	// parse declaration and create abstract syntax tree (ast)
	// walk ast to make transpiled file
	println('finished transpiling\n')
}

enum YTokenKind {
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
	return tokenize_pattern(input, r'\s', .white_space, false)
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