/*  $Id$

    Copyright (c) 1990 Jan Wielemaker. All rights reserved.
    jan@swi.psy.uva.nl

    Purpose: implementation of history system
*/

:- module($history,
	[ read_history/6
	, $clean_history/0
	]).

%   read_history(+History, +Help, +DontStore, +Prompt, -Term, -Bindings)
%   Give a prompt using Prompt. The sequence '%w' is substituted with the
%   current event number. Then read a term from the input stream and perform
%   the history expansion. Return the expanded term and the bindings of the
%   variables as with read/2.
%   entering the term History makes read_history/5 print the history.
%   Help specifies the help command.
%   DontStore is a list of events that need not be stored.

%   When read_history reads a term of the form $silent(Goal), it will
%   call Goal and pretend it has not seen anything.  This hook is used
%   by the GNU-Emacs interface to for communication between GNU-EMACS
%   and SWI-Prolog.

read_history(History, Help, DontStore, Prompt, Term, Bindings) :-
	repeat, 
	    prompt_history(Prompt), 
	    $raw_read(Raw), 
	    read_history_(History, Help, DontStore, Raw, Term, Bindings), !.

read_history_(History, _, _, History, _, _) :-
	list_history, !, 
	fail.
read_history_(Show, Help, _, Help, _, _) :-
	help_history(Show, Help), !, 
	fail.
read_history_(History, Help, DontStore, Raw, Term, Bindings) :-
	expand_history(Raw, Expanded, Changed), 
	save_history_line(Expanded),
	$term_to_atom(Term0, Expanded, Bindings0, 1),
	(   var(Term0)
	->  Term = Term0,
	    Bindings = Bindings0
	;   Term0 = $silent(Goal)
	->  user:ignore(Goal),
	    $raw_read(NewRaw),
	    read_history_(History, Help, DontStore, NewRaw, Term, Bindings)
	;   save_event(DontStore, Expanded), 
	    write_event(Expanded, Changed), 
	    Term = Term0,
	    Bindings = Bindings0
	).


write_event(_, false) :- !.
write_event(Event, true) :-
	format('~w.~n', [Event]).

%   list_history
%   Write history events to the current output stream.

list_history :-
	flag($last_event, Last, Last), 
	history_depth_(Depth), 
	plus(First, Depth, Last), 
	between(First, Last, Nr), 
	    recorded($history_list, Nr/Event), 
	    format('~t~w   ~8|~w.~n', [Nr, Event]), 
	fail.
list_history.

$clean_history :-
	recorded($history_list, _, Ref),
	    erase(Ref),
	fail.
$clean_history :-
	flag($last_event, _, 0).

help_history(Show, Help) :-
    $ttyformat('History Commands:~n'), 
    $ttyformat('    !!.              Repeat last query~n'), 
    $ttyformat('    !nr.             Repeat query numbered <nr>~n'), 
    $ttyformat('    !str.            Repeat last query starting with <str>~n'), 
    $ttyformat('    !?str.           Repeat last query holding <str>~n'), 
    $ttyformat('    ^old^new.        Substitute <old> into <new> of last query~n'), 
    $ttyformat('    !nr^old^new.     Substitute in query numbered <nr>~n'), 
    $ttyformat('    !str^old^new.    Substitute in query starting with <str>~n'), 
    $ttyformat('    !?str^old^new.   Substitute in query holding <str>~n'), 
    $ttyformat('    ~w.~21|Show history list~n', [Show]), 
    $ttyformat('    ~w.~21|Show this list~n', [Help]).

%   prompt_history(+Prompt)
%   Give prompt, substituting '%!' by the event number.

prompt_history(Prompt) :-
	flag($last_event, Old, Old), 
	succ(Old, This), 
	atom_codes(Prompt, SP),
	atom_codes(This, ST),
	(   substitute("%!", ST, SP, String)
	->  prompt1(String)
	;   prompt1(Prompt)
	),
	ttyflush.

%   save_event(+Event)
%   Save Event in the history system. Remove possibly outdated events.

save_history_line(Line) :-
	feature(readline, true),
	string_concat(Line, '.', CompleteLine),
	catch(user:rl_add_history(CompleteLine), _, fail), !.
save_history_line(_).

save_event(Dont, Event) :-
	memberchk(Event, Dont), !.
save_event(_, Event) :-
	flag($last_event, Old, Old), 
	succ(Old, New), 
	flag($last_event, _, New), 
	recorda($history_list, New/Event), 
	history_depth_(Depth), 
	remove_history(New, Depth).

remove_history(New, Depth) :-
	New - Depth =< 0, !.
remove_history(New, Depth) :-
	Remove is New - Depth,
	recorded($history_list, Remove/_, Ref), !,
	erase(Ref).
remove_history(_, _).	

%    history_depth_(-Depth)
%    Define the depth to which to keep the history.

history_depth_(N) :-
	feature(history, N),
	integer(N), !.
history_depth_(15).

%    expand_history(+Raw, -Expanded)
%    Expand Raw using the available history list. Expandations performed
%    are:
%    
%	^old^new	% Substitute
%	!match		% Last event starting <match>
%	!?match		% Last event matching <match>
%	!n		% Event nr. <n>
%	!spec^old^new	% substitute <by> <new> in last event <spec>
%	!!		% last event
%	
%    Note: the first character after a '!' should be a letter or number to
%    avoid problems with the cut.

expand_history(Raw, Expanded, Changed) :-
	atom_chars(Raw, RawString), 
	expand_history2(RawString, ExpandedString, Changed), 
	atom_chars(Expanded, ExpandedString), !.

expand_history2([^|Rest], Expanded, true) :- !, 
	get_last_event(Last), 
	old_new(Rest, Old, New, []), 
	substitute_warn(Old, New, Last, Expanded).
expand_history2(String, Expanded, Changed) :-
	expand_history3(String, Expanded, Changed).

expand_history3([!, C|Rest], [!|Expanded], Changed) :-
	not_event_char(C), !, 
	expand_history3([C|Rest], Expanded, Changed).
expand_history3([!|Rest], Expanded, true) :- !, 
	match_event(Rest, Event, NewRest), 
	append(Event, RestExpanded, Expanded), !, 
	expand_history3(NewRest, RestExpanded, _).
expand_history3([H|T], [H|R], Changed) :- !, 
	expand_history3(T, R, Changed).
expand_history3([], [], false).

%   old_new(+Spec, -Old, -New, -Left)
%   Takes Spec as a substitute specification without the first '^' and
%   returns the Old and New substitute patterns as well s possible text
%   left.

old_new([^|Rest], [], New, Left) :- !, 
	new(Rest, New, Left).
old_new([H|Rest], [H|Old], New, Left) :-
	old_new(Rest, Old, New, Left).

new([], [], []) :- !.
new([^|Left], [], Left) :- !.
new([H|T], [H|New], Left) :-
	new(T, New, Left).

%   get_last_event(-String)
%   return last event typed as a string

get_last_event(Event) :-
	recorded($history_list, _/Atom), 
	atom_chars(Atom, Event), !.
get_last_event(_) :-
	$ttyformat('! No such event~n'),
	fail.

%   substitute(+Old, +New, +String, -Substituted)	
%   substitute first occurence of Old in String by New

substitute(Old, New, String, Substituted) :-
	append(Head, OldAndTail, String), 
	append(Old, Tail, OldAndTail), !, 
	append(Head, New, HeadAndNew), 
	append(HeadAndNew, Tail, Substituted), !.

substitute_warn(Old, New, String, Substituted) :-
	substitute(Old, New, String, Substituted), !.
substitute_warn(_, _, _, _) :-
	$ttyformat('! bad substitution~n'),
	fail.

%   match_event(+Spec, -Event, -Rest)
%   Use Spec as a specification of and event and return the event as Event
%   and what is left of Spec as Rest.

match_event(Spec, Event, Rest) :-
	find_event(Spec, RawEvent, Rest0), !, 
	substitute_event(Rest0, RawEvent, Event, Rest).
match_event(_, _, _) :-
	$ttyformat('! No such event~n'),
	fail.

substitute_event([^|Spec], RawEvent, Event, Rest) :- !, 
	old_new(Spec, Old, New, Rest), 
	substitute(Old, New, RawEvent, Event).
substitute_event(Rest, Event, Event, Rest).

alpha(A) :- atom_char(A, C), between(0'a, 0'z, C).
alpha(A) :- atom_char(A, C), between(0'A, 0'Z, C).
alpha('_').

digit(A) :- atom_char(A, C), between(0'0, 0'9, C).

alpha_digit(C) :-
	alpha(C).
alpha_digit(C) :-
	digit(C).

not_event_char(C) :- alpha_digit(C), !, fail.
not_event_char(?) :- !, fail.
not_event_char(!) :- !, fail.
not_event_char(_).

find_event([?|Rest], Event, Left) :- !, 
	take_string(Rest, String, Left), 
	matching_event(substring, String, Event).
find_event([!|Left], Event, Left) :- !, 
	get_last_event(Event).
find_event([N|Rest], Event, Left) :-
	digit(N), !, 
	take_number([N|Rest], String, Left), 
	number_chars(Number, String), 
	recorded($history_list, Number/Atom), 
	atom_chars(Atom, Event).
find_event(Spec, Event, Left) :-
	take_string(Spec, String, Left), 
	matching_event(prefix, String, Event).

take_string([C|Rest], [C|String], Left) :-
	alpha_digit(C), !, 
	take_string(Rest, String, Left).
take_string([C|Rest], [], [C|Rest]) :- !.	
take_string([], [], []).
	
take_number([C|Rest], [C|String], Left) :-
	digit(C), !, 
	take_string(Rest, String, Left).
take_number([C|Rest], [], [C|Rest]) :- !.	
take_number([], [], []).

%   matching_event(+Where, +String, -Event)
%   Return first event with prefix String as a Prolog string.

matching_event(prefix, String, Event) :-
	recorded($history_list, _/AtomEvent), 
	atom_chars(AtomEvent, Event), 
	append(String, _, Event), !.
matching_event(substring, String, Event) :-
	recorded($history_list, _/AtomEvent), 
	atom_chars(AtomEvent, Event), 
	append(_, MatchAndTail, Event), 
	append(String, _, MatchAndTail), !.	
