Nonterminals expr match branch sttm sttms.
Terminals
	integer definition
	add sub mul 'div' 'rem'
	match_kw else_kw
	branch_arrow branch_bar asgn semicolon.

Rootsymbol sttms.

%% Precedence
Left 100 add.
Left 100 sub.
Left 200 mul.
Left 200 'div'.
Left 200 'rem'.

expr -> integer : '$1'.
expr -> definition : '$1'.

expr -> expr add expr : {add, '$1', '$3'}.
expr -> expr sub expr : {sub, '$1', '$3'}.
expr -> expr mul expr : {mul, '$1', '$3'}.
expr -> expr 'div' expr : {'div', '$1', '$3'}.
expr -> expr 'rem' expr : {'rem', '$1', '$3'}.

branch -> branch_bar else_kw branch_arrow expr: [{'guard', 'else', '$4'}].
branch -> branch_bar expr branch_arrow expr branch: [{'guard', '$2', '$4'}] ++ '$5'.
match -> match_kw expr branch: {'guards', '$2', '$3'}.
expr -> match: '$1'.

sttm -> definition asgn expr : {asgn, '$1', '$3'}.

sttms -> sttm: ['$1'].
sttms -> sttm semicolon sttm:
        ['$1', '$3'].

Erlang code.
