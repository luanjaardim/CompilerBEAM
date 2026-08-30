Nonterminals
	basic match_expr expr
	list list_aux tuple tuple_aux
	recv_def send_def
	call_func func_params lambda_def lambda_def_aux
	fn_def clause clause_aux arguments guards guards_or guards_and block
	match map map_fields map_match map_match_fields emp_map
	definitions def mod_def mod_def_aux sttms sttm.

Terminals
	integer string var atom
	'+' '-' '*' '/' 'div' 'rem'
	'=' '<-' '==' '/=' '>' '<' '>=' '=<' '::'
	fn_call match_kw if_kw 'true' 'false' pub_kw mod_kw fn_kw fn_par_kw
	'(' ')' '[' ']' '{' '}'
	'||' '&&' '=>' '?' '!' '|' '#' ';' ':' ',' eof.

Rootsymbol definitions.

%% Precedence
Left 100 '+'.
Left 100 '-'.
Left 200 '*'.
Left 200 '/'.
Left 200 'div'.
Left 200 'rem'.

Left 50 '=='.
Left 50 '/='.
Left 50 '>'.
Left 50 '<'.
Left 50 '>='.
Left 50 '=<'.

Right 20 '!'.

Left 10 '||'.
Left 10 '&&'.
Left 10 '::'.

Left 6 '=>'.
Right 5 '='.

basic -> integer: '$1'.
basic -> string : '$1'.
basic -> var    : '$1'.
basic -> atom   : '$1'.
basic -> 'true' : '$1'.
basic -> 'false': '$1'.
basic -> tuple  : '$1'.
basic -> list   : '$1'.

match_expr -> '(' match_expr ')': '$2'.
match_expr -> basic: '$1'.
match_expr -> map_match: '$1'.
match_expr -> emp_map: '$1'.
% List append
match_expr -> expr '::' expr: {cons, '$2', '$1', '$3'}.
% Argument assignment
match_expr -> var '<-' expr: {match, '$2', '$1', '$3'}.

expr -> match_expr: '$1'.
expr -> '(' expr ')': '$2'.

% Arithmetical operations
expr -> expr '+' expr : {op, '$2', '$1', '$3'}.
expr -> expr '-' expr : {op, '$2', '$1', '$3'}.
expr -> expr '*' expr : {op, '$2', '$1', '$3'}.
expr -> expr '/' expr : {op, '$2', '$1', '$3'}.
expr -> expr 'div' expr : {op, '$2', '$1', '$3'}.
expr -> expr 'rem' expr : {op, '$2', '$1', '$3'}.

% Bollean operations
expr -> expr '==' expr: {op, '$2', '$1', '$3'}.
expr -> expr '/=' expr: {op, '$2', '$1', '$3'}.
expr -> expr '>'  expr: {op, '$2', '$1', '$3'}.
expr -> expr '<'  expr: {op, '$2', '$1', '$3'}.
expr -> expr '>=' expr: {op, '$2', '$1', '$3'}.
expr -> expr '=<' expr: {op, '$2', '$1', '$3'}.

% Tuple definition
tuple_aux -> '}' : [].
tuple_aux -> expr '}': ['$1'].
tuple_aux -> expr ',' tuple_aux: ['$1' | '$3'].
tuple -> '{' tuple_aux: {tuple, '$1', '$2'}.

% List definition
list_aux -> ']' : {nil, '$1'}.
list_aux -> expr ']': {cons, '$2', '$1', {nil, '$2'}}.
list_aux -> expr ',' list_aux: {cons, '$2', '$1', '$3'}.
list -> '[' list_aux : '$2'.

% Function as an expr, anonymous lambda function
expr -> lambda_def : '$1'.
lambda_def_aux -> arguments block '|' '(' lambda_def_aux : [{'clause', 'none', {'args', '$1'}, {'guards', []}, '$2'} | '$5'].
lambda_def_aux -> arguments block : [{'clause', 'none', {'args', '$1'}, {'guards', []}, '$2'}].
lambda_def -> fn_kw '(' lambda_def_aux : {'lambda', '$1', '$3'}.
lambda_def -> fn_par_kw lambda_def_aux : {'lambda', '$1', '$2'}.

% Function call
expr -> call_func: '$1'.
func_params -> ')' : [].
func_params -> expr ')' : ['$1'].
func_params -> expr ',' func_params : ['$1'] ++ '$3'.
call_func -> fn_call func_params : {'$1', '$2'}.
call_func -> expr '(' func_params : {'call', '$2', '$1', '$3'}.

% Match expression
expr -> match: '$1'.
match -> match_kw expr clause_aux: {'case', '$1', '$2', '$3'}.

% Send messages
expr -> send_def: '$1'.
send_def -> expr '!' expr: {op, '$2', '$1', '$3'}.

% Receive messages
expr -> recv_def: '$1'.
recv_def -> '?' clause: {recv, '$1', ['$2']}.
recv_def -> '?' clause clause_aux: {recv, '$1', ['$2' | '$3']}.

% Map definition
expr -> map: '$1'.
map_fields -> match_expr '=' expr: [{map_field_assoc, '$2', '$1', '$3'}].
map_fields -> map_fields ',' map_fields : '$1' ++ '$3'.
map -> '#' '{' map_fields '}': {map, '$1', '$3'}.
map -> var '#' '{' map_fields '}': {map, '$2', '$1', '$4'}.
map_match_fields -> match_expr ':' expr: [{map_field_exact, '$2', '$1', '$3'}].
map_match_fields -> map_match_fields ',' map_match_fields : '$1' ++ '$3'.
map_match -> '#' '{' map_match_fields '}': {map, '$1', '$3'}.
emp_map -> '#' '{' '}': {map, '$1', []}.

% Clause: Args, Guards and Body definition
guards_and -> expr: ['$1'].
guards_and -> expr '&&' guards_and: ['$1' | '$3'].
guards_or -> guards_and '||' guards_or: ['$1'] ++ '$3'.
guards_or -> guards_and : ['$1'].
guards -> if_kw guards_or: '$2'.
arguments -> match_expr ',' arguments: ['$1'] ++ '$3'.
arguments -> match_expr ')': ['$1'].
arguments -> ')': [].
clause -> '(' arguments guards block : {'clause', '$1', {'args', '$2'}, {'guards', '$3'}, '$4'}.
clause -> '(' arguments block : {'clause', '$1', {'args', '$2'}, {'guards', []}, '$3'}.

% Function definition
clause_aux -> '|' clause clause_aux: ['$2' | '$3'].
clause_aux -> '|' clause: ['$2'].
fn_def  -> fn_kw var '=' clause: {function, '$2', ['$4']}.
fn_def  -> fn_kw var '=' clause clause_aux: {function, '$2', ['$4' | '$5']}.

sttm -> match_expr '=' expr: {match, '$2', '$1', '$3'}.
sttm -> fn_def: '$1'.
sttm -> expr: return_error("Expecting a Statement, not an Expression. Discard the value with: _ = ...", '$1').
sttms -> sttm : ['$1'].
sttms -> sttms ';' sttm: ['$3' | '$1'].
block -> '{' sttms '}': lists:reverse('$2').
block -> '{' sttms ';' expr '}': lists:reverse(['$4' | '$2']).
block -> '=>' expr: ['$2'].
block -> expr: return_error("Was expecting an body, not an expression.", '$1').

def -> fn_def: '$1'.
def -> pub_kw fn_def: {pub, '$2'}.
def -> def ';': return_error("Was not expecting a ';' after this definition.", '$2').

mod_def_aux -> def '}' : ['$1'].
mod_def_aux -> def mod_def_aux : ['$1' | '$2'].
mod_def_aux -> sttm : return_error("At a Module main definition, a statement is not valid.", '$1').
mod_def -> mod_kw var '{' mod_def_aux : {module, '$1', '$2', [], '$4'}.
mod_def -> mod_kw fn_call arguments '{' mod_def_aux : {module, '$1', '$2', '$3', '$5'}.
mod_def -> mod_kw var '(' arguments '{' mod_def_aux : {module, '$1', '$2', '$4', '$6'}.
% Empty modules error
mod_def -> mod_kw var '(' arguments '{' '}' : return_error("Empty Module.", '$2').
mod_def -> mod_kw var '{' '}' : return_error("Empty Module.", '$2').

definitions -> mod_def definitions : ['$1' | '$2'].
definitions -> eof : ['$1'].

Erlang code.
