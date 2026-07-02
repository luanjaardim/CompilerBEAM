Nonterminals
	proc_def_events proc_def_choices proc_def proc proc_aux proc_args
	channel_tuple channel_def_aux channel_def sync_def paralel_def datatype_variants
	seq seq_aux expr def definitions.

Terminals
	integer var proc_call
	'+' '-' '*' '/' div rem
	'==' '/=' '>' '<' '>=' '=<' ':'
	asgn true false channel nametype datatype
	'(' ')' '[' ']' '{' '}' '[]' '->' '--#'
	'[|' '{|' '|}' '|]'
	'?' '!' '|' '|||' ';' ',' '.' '..' eof.

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
expr -> proc : '$1'.
expr -> 'true' : '$1'.
expr -> 'false': '$1'.

% Arithmetical operations
expr -> expr '+' expr : {expr, '$2', '$1', '$3'}.
expr -> expr '-' expr : {expr, '$2', '$1', '$3'}.
expr -> expr '*' expr : {expr, '$2', '$1', '$3'}.
expr -> expr '/' expr : {expr, '$2', '$1', '$3'}.
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
seq_aux -> '>' : [].
seq_aux -> expr '>': ['$1'].
seq_aux -> expr ',' seq_aux : ['$1' | '$3'].
seq -> '<' seq_aux : {seq, '$1', '$2'}.
expr -> seq: '$1'.

% Send to channel
expr -> expr '!' expr: {op, '$2', '$1', '$3'}.
% Recv from channel
expr -> expr '?' expr: {op, '$2', '$1', '$3'}.

sync_def -> proc asgn proc '[|' '{|' channel_def_aux '|}' '|]' proc : {sync, '$1', {sync_channel, '$3', '$9', '$6'}}.
paralel_def -> proc asgn proc '|||' proc : {paralel, '$1', '$3', '$5'}.

proc_args -> ')' : [].
proc_args -> expr ')' : ['$1'].
proc_args -> expr ',' proc_args : ['$1' | '$3'].
proc_aux -> '(' proc_args proc_aux : ['$2' | '$3'].
proc_aux -> '(' proc_args : ['$2'].
proc -> var proc_aux : {proc_call, '$1', '$2'}.
proc -> var : '$1'.

proc_def_events -> '(' proc_def_events ')': '$2'.
proc_def_events -> expr: ['$1'].
proc_def_events -> expr '->' proc_def_events: ['$1' | '$3'].
proc_def_events -> expr '->' '(' proc_def_choices ')': ['$1', {choices, '$4'}].
proc_def_choices -> '(' proc_def_choices ')': '$2'.
proc_def_choices -> proc_def_events: [{events, '$1'}].
proc_def_choices -> proc_def_choices '[]' proc_def_choices: '$1' ++ '$3'.
proc_def -> proc asgn proc_def_choices: {proc, '$1', {body, {choices, '$3'}}}.

channel_def_aux -> var : ['$1'].
channel_def_aux -> var ',' channel_def_aux : ['$1' | '$3'].
channel_def -> channel channel_def_aux : {channel, 0, '$2'}.
channel_tuple -> expr : 1.
channel_tuple -> expr '.' channel_tuple: 1 + '$3'.
channel_def -> channel channel_def_aux ':' channel_tuple : {channel, '$4', '$2'}.
channel_def -> '--#' var channel_def : {extern, '$2', '$3'}.

datatype_variants -> var : ['$1'].
datatype_variants -> var '|' datatype_variants : [ '$1' | '$3' ].

def -> nametype var asgn expr: {ignore}.
def -> datatype var asgn datatype_variants : {datatype, '$4'}.
def -> sync_def: '$1'.
def -> paralel_def: '$1'.
def -> proc_def: '$1'.
def -> channel_def: '$1'.

definitions -> def definitions : ['$1' | '$2'].
definitions -> eof : [].

Erlang code.
