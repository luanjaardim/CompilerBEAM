Nonterminals
	proc_def_events proc_def_choices proc_def
	channel_tuple channel_def_aux channel_def sync_def datatype_variants
	set set_aux expr def definitions.

Terminals
	integer var
	'+' '-' '*' '/' div rem
	'==' '/=' '>' '<' '>=' '=<' ':'
	asgn true false channel nametype datatype
	'(' ')' '[' ']' '{' '}' '[]' '->' '--#'
	'[|' '{|' '|}' '|]'
	'?' '!' '|' ';' ',' '.' '..' eof.

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
Right 20 '?'.

expr -> '(' expr ')' : '$2'.
expr -> integer : '$1'.
expr -> var : '$1'.
expr -> 'true' : '$1'.
expr -> 'false': '$1'.

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

% Sets
expr -> '{' integer '..' integer '}' : {set, {range, '$2', '$4'}}.
set_aux -> '}' : [].
set_aux -> expr '}': ['$1'].
set_aux -> expr ',' set_aux : ['$1' | '$3'].
set -> '{' set_aux : {tuple, '$1', '$2'}.
expr -> set: '$1'.

% Send to channel
expr -> expr '!' expr: {op, '$2', '$1', '$3'}.
% Recv from channel
expr -> expr '?' expr: {op, '$2', '$1', '$3'}.

sync_def -> var asgn var '[|' '{|' channel_def_aux '|}' '|]' var : {sync, '$1', {sync_channel, '$3', '$9', '$6'}}.

proc_def_events -> expr: ['$1'].
proc_def_events -> expr '->' proc_def_events: ['$1' | '$3'].
proc_def_choices -> proc_def_events : ['$1'].
proc_def_choices -> proc_def_events '[]' proc_def_choices: ['$1' | '$3'].
proc_def -> var asgn proc_def_choices: {proc, '$1', {choices, '$3'}}.

channel_def_aux -> var : ['$1'].
channel_def_aux -> var ',' channel_def_aux : ['$1' | '$3'].
channel_def -> channel channel_def_aux : {channel, 0, '$2'}.
channel_tuple -> expr : 1.
channel_tuple -> expr '.' channel_tuple: 1 + '$3'.
channel_tuple -> ':' channel_tuple: '$2'.
channel_def -> channel channel_def_aux channel_tuple : {channel, '$3', '$2'}.
channel_def -> '--#' var channel channel_def_aux channel_tuple : {extern, '$2', '$5', '$4'}.

datatype_variants -> var : {ignore}.
datatype_variants -> var '|' datatype_variants : {ignore}.

def -> nametype var asgn expr: {ignore}.
def -> datatype var asgn datatype_variants : {ignore}.
def -> sync_def: '$1'.
def -> proc_def: '$1'.
def -> channel_def: '$1'.

definitions -> def definitions : ['$1' | '$2'].
definitions -> eof : [].

Erlang code.
