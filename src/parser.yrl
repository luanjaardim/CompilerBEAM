Nonterminals
	arguments lambda_def lambda_def_aux fn_definition func_params clauses clause_aux guards guards_or guards_and
	expr match branch sttm sttms block mod_decl mod_decl_aux send_def send_def_aux fn_decl def definitions
	tuple tuple_aux list list_aux call_func.
Terminals
	integer string var atom
	'+' '-' '*' '/' 'div' 'rem'
	'==' '/=' '>' '<' '>=' '=<' '::'
	fn_call asgn
	match_kw if_kw 'true' 'false' pub_kw mod_kw fn_kw fn_par_kw
	'(' ')' '[' ']' '{' '}'
	'||' '&&' '=>' '?' '!' '|' ';' ',' eof.

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
Left 50 '=>'.

Right 20 '!'.

Left 10 '||'.
Left 10 '&&'.
Left 10 '::'.

expr -> '(' expr ')' : '$2'.
expr -> integer : '$1'.
expr -> string : '$1'.
expr -> var : '$1'.
expr -> atom : '$1'.
expr -> 'true' : '$1'.
expr -> 'false': '$1'.
expr -> tuple: '$1'.
expr -> list: '$1'.

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

% Send messages
send_def_aux -> expr: '$1'.
send_def -> expr '!' send_def_aux: {op, '$2', '$1', '$3'}.
expr -> send_def: '$1'.
% List append
expr -> expr '::' expr: {cons, '$2', '$1', '$3'}.

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

% Function call
func_params -> expr ')' : ['$1'].
func_params -> expr ',' func_params : ['$1'] ++ '$3'.
call_func -> fn_call func_params : {'$1', '$2'}.
call_func -> fn_call ')' : {'$1', []}.
expr -> call_func: '$1'.

% TODO: change the expr of a match branch to a match_expr
% TODO: change this guard to something like a clause
branch -> '|' expr '=>' block : [{'clause', '$1', {'args', ['$2']}, {'guards', []}, '$4'}].
branch -> '|' expr '=>' block branch: [{'clause', '$1', {'args', ['$2']}, {'guards', []}, '$4'} | '$5'].
branch -> '|' expr guards '=>' block branch: [{'clause', '$1', {'args', ['$2']}, {'guards', '$3'}, '$5'} | '$6'].
match -> match_kw expr branch: {'case', '$1', '$2', '$3'}.
expr -> match: '$1'.

guards_and -> expr: ['$1'].
guards_and -> expr '&&' guards_and: ['$1' | '$3'].
guards_or -> guards_and '||' guards_or: ['$1'] ++ '$3'.
guards_or -> guards_and : ['$1'].
guards -> if_kw guards_or: '$2'.
arguments -> expr ',' arguments: ['$1'] ++ '$3'.
arguments -> expr ')': ['$1'].
arguments -> ')': [].
fn_definition -> '(' arguments guards block : {'clause', '$1', {'args', '$2'}, {'guards', '$3'}, '$4'}.
fn_definition -> '(' arguments block : {'clause', '$1', {'args', '$2'}, {'guards', []}, '$3'}.

% Function as an expr, anonymous lambda function
expr -> lambda_def : '$1'.
lambda_def_aux -> arguments block '|' '(' lambda_def_aux : [{'clause', 'none', {'args', '$1'}, {'guards', []}, '$2'} | '$5'].
lambda_def_aux -> arguments block : [{'clause', 'none', {'args', '$1'}, {'guards', []}, '$2'}].
lambda_def -> fn_kw '(' lambda_def_aux : {'lambda', '$1', '$3'}.
lambda_def -> fn_par_kw lambda_def_aux : {'lambda', '$1', '$2'}.

% Receive messages
expr -> '?' fn_definition: {recv, '$1', ['$2']}.
expr -> '?' fn_definition clause_aux: {recv, '$1', ['$2' | '$3']}.

clauses -> asgn fn_definition clause_aux: ['$2' | '$3'].
clauses -> asgn fn_definition: ['$2'].
clause_aux -> '|'  fn_definition clause_aux: ['$2' | '$3'].
clause_aux -> '|'  fn_definition: ['$2'].

sttm -> send_def : '$1'.
sttm -> call_func : '$1'.
sttm -> fn_decl : '$1'.
sttm -> tuple asgn expr : {match, '$2', '$1', '$3'}.
sttm -> var asgn expr : {match, '$2', '$1', '$3'}.
fn_decl -> var clauses : {function, '$1', '$2'}.
mod_decl_aux -> def '}' : ['$1'].
mod_decl_aux -> def mod_decl_aux : ['$1' | '$2'].
mod_decl -> mod_kw var '{' mod_decl_aux : {module, '$1', '$2', '$4'}.

def -> mod_decl: '$1'.
def -> fn_decl: '$1'.
def -> pub_kw fn_decl: {pub, '$2'}.

sttms -> expr: ['$1'].
sttms -> sttm ';' : ['$1'].
sttms -> sttm ';' sttms: ['$1'] ++ '$3'.

block -> '{' sttms '}': '$2'.

definitions -> def definitions : ['$1' | '$2'].
definitions -> eof : ['$1'].

Erlang code.
