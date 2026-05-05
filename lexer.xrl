Definitions.
DIGIT = [0-9]
NAME = [a-zA-Z_]

Rules.
% Whitespace skip
[\s\n\t\r]+      : skip_token.
\$.*\n           : skip_token.

% Operators
\+   : {token, {add, TokenLoc}}.
\-   : {token, {sub, TokenLoc}}.
\*   : {token, {mul, TokenLoc}}.
\/   : {token, {'div', TokenLoc}}.
\%   : {token, {'rem', TokenLoc}}.
=    : {token, {asgn, TokenLoc}}.
=\|  : {token, {'=|', TokenLoc}}.
==   : {token, {eq, TokenLoc}}.
\!=  : {token, {neq, TokenLoc}}.
>    : {token, {grt, TokenLoc}}.
<    : {token, {lst, TokenLoc}}.
>=   : {token, {gte, TokenLoc}}.
<=   : {token, {lse, TokenLoc}}.
=>   : {token, {'=>', TokenLoc}}.

% Separators
\(    : {token, {'(', TokenLoc}}.
\)    : {token, {')', TokenLoc}}.
\[    : {token, {'[', TokenLoc}}.
\]    : {token, {']', TokenLoc}}.
\{    : {token, {'{', TokenLoc}}.
\}    : {token, {'}', TokenLoc}}.
\:\:  : {token, {'::', TokenLoc}}.
\:    : {token, {':', TokenLoc}}.
;     : {token, {';', TokenLoc}}.
,     : {token, {',', TokenLoc}}.
@     : {token, {'@', TokenLoc}}.
#     : {token, {'#', TokenLoc}}.
\|     : {token, {'|', TokenLoc}}.

% Reserved keywords
if    : {token, {if_kw, TokenLoc}}. % TODO: implement guard conditions
match : {token, {match_kw, TokenLoc}}.
else  : {token, {else_kw, TokenLoc}}.
true  : {token, {'true', TokenLoc}}.
false : {token, {'false', TokenLoc}}.

\-?{DIGIT}+ : {token, {integer, TokenLoc, list_to_integer(TokenChars)}}.
{NAME}({NAME}|{DIGIT})*   : {token, {definition, TokenLoc, TokenChars}}.
{NAME}({NAME}|{DIGIT})*\( : {token, {fn_call, TokenLoc, lists:droplast(TokenChars)}}.

Erlang code.
