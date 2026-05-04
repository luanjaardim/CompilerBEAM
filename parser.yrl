Nonterminals 
	arguments fn_definition call_func func_params
	expr match branch sttm sttms block tests.
Terminals
	integer definition
	add sub mul 'div' 'rem'
	fn_call asgn
	match_kw else_kw 'true' 'false'
	'(' ')' '[' ']' '{' '}'
	'=>' '|' ';' ','.

Rootsymbol sttms.

%% Precedence
Left 100 add.
Left 100 sub.
Left 200 mul.
Left 200 'div'.
Left 200 'rem'.

expr -> '(' expr ')' : '$2'.
expr -> integer : '$1'.
expr -> definition : '$1'.
expr -> 'true' : '$1'.
expr -> 'false': '$1'.

expr -> expr add expr : {add, '$1', '$3'}.
expr -> expr sub expr : {sub, '$1', '$3'}.
expr -> expr mul expr : {mul, '$1', '$3'}.
expr -> expr 'div' expr : {'div', '$1', '$3'}.
expr -> expr 'rem' expr : {'rem', '$1', '$3'}.

% Function call
func_params -> expr ')' : ['$1'].
func_params -> expr ',' func_params : ['$1'] ++ '$3'.
call_func -> fn_call func_params : {'$1', '$2'}.
call_func -> fn_call ')' : {'$1', []}.
expr -> call_func: '$1'.

% TODO: change the expr of a match branch to a match_expr
branch -> '|' else_kw '=>' block: [{'guard', 'else', '$4'}].
branch -> '|' expr '=>' block branch: [{'guard', '$2', '$4'}] ++ '$5'.
match -> match_kw expr branch: {'guards', '$2', '$3'}.
expr -> match: '$1'.

arguments -> definition ',' arguments: ['$1'] ++ '$3'.
arguments -> definition ')': ['$1'].
arguments -> ')': [].
fn_definition -> '(' arguments block : {'function', {'args', '$2'}, '$3'}.
expr -> fn_definition: '$1'.

sttm -> definition asgn expr : {asgn, '$1', '$3'}.

sttms -> expr: [{'return', '$1'}].
sttms -> sttm ';' : ['$1'].
sttms -> sttm ';' sttms: ['$1'] ++ '$3'.

block -> '{' sttms '}': '$2'.

Erlang code.
