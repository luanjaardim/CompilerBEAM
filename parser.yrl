Nonterminals 
	arguments fn_definition call_func func_params recv clauses clause_aux guards guards_or guards_and
	tuple tuple_aux expr match branch sttm sttms block fn_decl def definitions.
Terminals
	integer string var atom
	'+' '-' '*' '/' 'div' 'rem'
	'==' '/=' '>' '<' '>=' '=<'
	fn_call asgn
	match_kw if_kw 'true' 'false' pub_kw
	'(' ')' '[' ']' '{' '}'
	'||' '&&' '=>' '=|' '=?' '|' ';' ',' eof.

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

Left 10 '||'.
Left 10 '&&'.

expr -> '(' expr ')' : '$2'.
expr -> integer : '$1'.
expr -> string : '$1'.
expr -> var : '$1'.
expr -> atom : '$1'.
expr -> 'true' : '$1'.
expr -> 'false': '$1'.
expr -> tuple: '$1'.

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

recv -> '=?' fn_definition clause_aux: ['$2' | '$3'].
recv -> '=?' fn_definition: ['$2'].
clauses -> '=|' fn_definition clause_aux: ['$2' | '$3'].
clauses -> '=|' fn_definition: ['$2'].
clause_aux -> '|'  fn_definition clause_aux: ['$2' | '$3'].
clause_aux -> '|'  fn_definition: ['$2'].

sttm -> fn_decl : '$1'.
sttm -> var recv : {recv, '$1', '$2'}.
sttm -> var asgn expr : {match, '$2', '$1', '$3'}.
fn_decl -> var clauses : {function, '$1', '$2'}.
fn_decl -> var asgn fn_definition : {function, '$1', ['$3']}.
def -> pub_kw fn_decl: {pub, '$2'}.
def -> fn_decl: '$1'.

sttms -> expr: ['$1'].
sttms -> sttm ';' : ['$1'].
sttms -> sttm ';' sttms: ['$1'] ++ '$3'.

block -> '{' sttms '}': '$2'.

definitions -> def definitions : ['$1' | '$2'].
definitions -> eof : ['$1'].

Erlang code.
