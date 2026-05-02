Definitions.
DIGIT = [0-9]
NAME = [a-zA-Z_]

Rules.
% Whitespace skip
\s+      : skip_token.

% Operators
\+   : {token, {add, {TokenLine, TokenCol}}}.
\-   : {token, {sub, {TokenLine, TokenCol}}}.
\*   : {token, {mul, {TokenLine, TokenCol}}}.
\/   : {token, {'div', {TokenLine, TokenCol}}}.
\%   : {token, {'rem', {TokenLine, TokenCol}}}.
=    : {token, {asgn, {TokenLine, TokenCol}}}.
==   : {token, {eq, {TokenLine, TokenCol}}}.
\!=  : {token, {neq, {TokenLine, TokenCol}}}.
>    : {token, {grt, {TokenLine, TokenCol}}}.
<    : {token, {lst, {TokenLine, TokenCol}}}.
>=   : {token, {gte, {TokenLine, TokenCol}}}.
<=   : {token, {lse, {TokenLine, TokenCol}}}.
=>   : {token, {branch_arrow, {TokenLine, TokenCol}}}.

% Separators
\(    : {token, {op_par, {TokenLine, TokenCol}}}.
\)    : {token, {cl_par, {TokenLine, TokenCol}}}.
\[    : {token, {op_sqb, {TokenLine, TokenCol}}}.
\]    : {token, {cl_sqb, {TokenLine, TokenCol}}}.
\{    : {token, {op_bra, {TokenLine, TokenCol}}}.
\}    : {token, {cl_bra, {TokenLine, TokenCol}}}.
\:\:  : {token, {double_colon, {TokenLine, TokenCol}}}.
\:    : {token, {colon, {TokenLine, TokenCol}}}.
;     : {token, {semicolon, {TokenLine, TokenCol}}}.
@     : {token, {at, {TokenLine, TokenCol}}}.
#     : {token, {hash, {TokenLine, TokenCol}}}.
\|     : {token, {branch_bar, {TokenLine, TokenCol}}}.

% Reserved keywords
match : {token, {match_kw, {TokenLine, TokenCol}}}.
else  : {token, {else_kw, {TokenLine, TokenCol}}}.

\-?{DIGIT}+ : {token, {integer, {TokenLine, TokenCol}, list_to_integer(TokenChars)}}.
{NAME}({NAME}|{DIGIT})*  : {token, {definition, {TokenLine, TokenCol}, TokenChars}}.

Erlang code.
