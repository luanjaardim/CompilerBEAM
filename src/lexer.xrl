Definitions.
DIGIT = [0-9]
NAME = [a-zA-Z_]
WORD = {NAME}({NAME}|{DIGIT})*

Rules.
% Whitespace skip
[\s\n\t\r]+      : skip_token.
\$.*\n           : skip_token.

% Operators
\+   : {token, {'+', TokenLoc}}.
\-   : {token, {'-', TokenLoc}}.
\*   : {token, {'*', TokenLoc}}.
\/   : {token, {'/', TokenLoc}}.
\/\/ : {token, {'div', TokenLoc}}.
\%   : {token, {'rem', TokenLoc}}.
=    : {token, {'=', TokenLoc}}.
\?   : {token, {'?', TokenLoc}}.
\!   : {token, {'!', TokenLoc}}.
==   : {token, {'==', TokenLoc}}.
\!=  : {token, {'/=', TokenLoc}}.
>    : {token, {'>', TokenLoc}}.
<    : {token, {'<', TokenLoc}}.
>=   : {token, {'>=', TokenLoc}}.
<=   : {token, {'=<', TokenLoc}}.
=>   : {token, {'=>', TokenLoc}}.
&&   : {token, {'&&', TokenLoc}}.
\|\| : {token, {'||', TokenLoc}}.

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
#     : {token, {'#', TokenLoc}}.
\|     : {token, {'|', TokenLoc}}.

% Reserved keywords
if      : {token, {if_kw, TokenLoc}}.
pub     : {token, {pub_kw, TokenLoc}}.
match   : {token, {match_kw, TokenLoc}}.
mod     : {token, {mod_kw, TokenLoc}}.
fn\(    : {token, {fn_par_kw, TokenLoc}}.
fn      : {token, {fn_kw, TokenLoc}}.
true    : {token, {'true', TokenLoc}}.
false   : {token, {'false', TokenLoc}}.
__EOF__ : {token, {eof, TokenLoc}}.

\"[^\"]*\"  : {token, {string, TokenLoc, escape_string(TokenChars)}}.
%\"[^\"]*\"  : {token, {string, TokenLoc, lists:droplast(tl(TokenChars))}}.
\-?{DIGIT}+ : {token, {integer, TokenLoc, list_to_integer(TokenChars)}}.
@{WORD}  : {token, {atom, TokenLoc, list_to_atom(tl(TokenChars))}}.
{WORD}   : {token, {var, TokenLoc, list_to_atom(TokenChars)}}.
({WORD}|{WORD}\:{WORD})\( : {token, {fn_call, TokenLoc, lists:map(fun(S) -> list_to_atom(S) end, string:tokens(lists:droplast(TokenChars), ":"))}}.

Erlang code.
escape_string(S) ->
	Split = fun Rec([$\\, $n | Tl]) -> [$\n | Rec(Tl)];
		    Rec([$\\, $t | Tl]) -> [$\t | Rec(Tl)];
		    Rec([$\\, $r | Tl]) -> [$\r | Rec(Tl)];
		    Rec([C | Tl]) -> [C | Rec(Tl)];
		    Rec([]) -> [] end,
	Split(lists:droplast(tl(S))).
