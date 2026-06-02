Definitions.
DIGIT = [0-9]
NAME = [a-zA-Z_]
WORD = {NAME}({NAME}|{DIGIT})*

Rules.
% Whitespace skip
[\s\n\t\r]+      : skip_token.

% Operators
\+   : {token, {'+', TokenLoc}}.
\-   : {token, {'-', TokenLoc}}.
\*   : {token, {'*', TokenLoc}}.
\/   : {token, {'/', TokenLoc}}.
\/\/ : {token, {'div', TokenLoc}}.
\%   : {token, {'rem', TokenLoc}}.
=    : {token, {asgn, TokenLoc}}.
\?   : {token, {'?', TokenLoc}}.
\!   : {token, {'!', TokenLoc}}.
==   : {token, {'==', TokenLoc}}.
\!=  : {token, {'/=', TokenLoc}}.
>    : {token, {'>', TokenLoc}}.
<    : {token, {'<', TokenLoc}}.
>=   : {token, {'>=', TokenLoc}}.
<=   : {token, {'=<', TokenLoc}}.
=>   : {token, {'=>', TokenLoc}}.
->   : {token, {'->', TokenLoc}}.

% Separators
\(    : {token, {'(', TokenLoc}}.
\)    : {token, {')', TokenLoc}}.
\[\]  : {token, {'[]', TokenLoc}}.
\[\[  : {token, {'[[', TokenLoc}}.
\]\]  : {token, {']]', TokenLoc}}.
\{\|  : {token, {'{|', TokenLoc}}.
\|\}  : {token, {'|}', TokenLoc}}.
\[    : {token, {'[', TokenLoc}}.
\]    : {token, {']', TokenLoc}}.
\{    : {token, {'{', TokenLoc}}.
\}    : {token, {'}', TokenLoc}}.
\:\:  : {token, {'::', TokenLoc}}.
\:    : {token, {':', TokenLoc}}.
;     : {token, {';', TokenLoc}}.
,     : {token, {',', TokenLoc}}.
\.    : {token, {'.', TokenLoc}}.
\.\.  : {token, {'..', TokenLoc}}.
#     : {token, {'#', TokenLoc}}.
\|     : {token, {'|', TokenLoc}}.

% Reserved keywords
channel : {token, {'channel', TokenLoc}}.
true    : {token, {'true', TokenLoc}}.
false   : {token, {'false', TokenLoc}}.
__EOF__ : {token, {eof, TokenLoc}}.

\"[^\"]*\"  : {token, {string, TokenLoc, lists:droplast(tl(TokenChars))}}.
\-?{DIGIT}+ : {token, {integer, TokenLoc, list_to_integer(TokenChars)}}.
{WORD}   : {token, {var, TokenLoc, list_to_atom(TokenChars)}}.

Erlang code.
