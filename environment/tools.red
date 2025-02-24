Red [
	Title:	 "Red run-time debugging and helping tools"
	Author:	 "Nenad Rakocevic"
	File:	 %tools.red
	Tabs:	 4
	Rights:	 "Copyright (C) 2021 Red Foundation. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

system/tools: context [
	fun-stk:   make block! 10
	expr-stk:  make block! 10
	watching:  make block! 10
	profiling: make block! 10
	
	indent: 0
	hist-length: none
	
	dbg-usage: next {
	`help` or `?`: print a list of debugger's commands.
	`next` or `n` or just ENTER: evaluate next value.
	`continue` or `c`: exit debugging console but continue evaluation.
	`quit` or `q`: exit debugger and stop evaluation.
	`stack` or `s`: display the current calls and expression stack.
	`parents` or `p`: display the parents call stack.
	`:word`: outputs the value of `word`. If it is a `function!`, outputs the local context.
	`:a/b/c`: outputs the value of `a/b/c` path.
	`watch <word1> <word2>...`: watch one or more words. `w` can be used as shortcut for `watch`.
	`-watch <word1> <word2>...`: stop watching one or more words. `-w` can be used as shortcut for `-watch`.
	`+stack`  or `+s`: outputs expression stack on each new event.
	`-stack`  or `-s`: do not output expression stack on each new event.
	`+locals` or `+l`: output local context for each entry in the callstack.
	`-locals` or `-l`: do not output local context for each entry in the callstack.
	`+indent` or `+i`: indent the output of the expression stack.
	`-indent` or `-i`: do not indent the output of the expression stack.
	}
	
	options: context [
		debug: context [
			active?:		no
			show-stack?:	yes
			show-parents?:	no
			show-locals?:	no
			stack-indent?:	no
		]
		trace: context [
			indent?:		yes
		]
		profile: context [
			sort-by: 		'count
			types:			make typeset! [function! action! native! op!]
		]
	]
	
	calc-max: func [used [integer!] return: [integer!]][
		either system/console [system/console/size/x - used][72 - used]
	]
	
	show-context: function [ctx [function! object!]][
		foreach w words-of :ctx [
			prin out: rejoin ["  > " pad mold :w 10 ": "]
			prin mold/flat/part try [get/any :w] calc-max length? out
			either find [none true false unset] :w [print " (word!)"][prin lf]
		]
	]
	
	show-parents: function [event [word!]][
		collect-calls list: make block! 10
		unless empty? fun-stk [
			remove/part list find list first first skip tail fun-stk pick -2x-1 event = 'call
		]
		foreach [w pos] reverse/skip list 2 [
			if all [not unset? get/any w function? get/any w][
				if :w = 'debug [exit]					;-- avoid showing debugger's own call stack
				print ["Call:" w]
				if options/debug/show-locals? [show-context get :w]
			]
		]
	]
	
	show-stack: function [][
		prin either empty? head expr-stk ["^/-empty stack-"][lf]
		indent: 0
		foreach frame head expr-stk [
			unless integer? frame [
				forall frame [
					prin "Stack: "
					if options/debug/stack-indent? [loop indent [prin "  "]]
					print mold/part/flat first frame calc-max 7 + (indent * 2)
					if head? frame [indent: indent + 1]
				]
			]
		]
		prin lf
	]
	
	show-watching: function [][
		foreach w watching [
			prin out: rejoin ["Watch: " mold w ": "]
			print mold/flat/part get/any w calc-max length? out
		]
		unless empty? watching [print lf]
	]
	
	do-command: function [event [word!]][
		if value? 'ask [								;-- `ask` needs a console sub-system
			do [										;-- prevents `ask` from being compiled
				until [
					cmd: trim ask "debug> "
					case [
						cmd = #":" [
							print ["==" mold get/any load next cmd]
						]
						find "+-" cmd/1 [
							mode?: cmd/1 = #"+"
							switch first list: load/all next cmd [
								watch w [
									list: next list
									either mode? [append watching list][
										foreach w list [try [remove find watching to-word w]]
									]
								]
								parents p [options/debug/show-parents?: mode?]
								stack   s [options/debug/show-stack?:   mode?]
								locals  l [options/debug/show-locals?:  mode?]
								indent  i [options/debug/stack-indent?: mode?]
							]
						]
						'else [
							unless empty? list: load/all cmd [
								switch/default list/1 [
									parents p	[show-parents event]
									stack s		[show-stack]
									next n		[clear cmd]
									continue c  [options/debug/active?: no clear cmd]
									quit q		[halt]
									help ?		[print dbg-usage]
								][
									print "Unknown command!"
								]
							]
						]
					]
					empty? cmd
				]
			]
		]
	]

	debugger: function [
		event  [word!]
		code   [any-block! none!]
		offset [integer!]
		value  [any-type!]
		ref	   [any-type!]
		frame  [pair!]
		/extern expr-stk hist-length
	][
		store: [
			either empty? expr-stk [
				append/only expr-stk to-paren reduce [:value]
			][
				append/only last expr-stk :value
			]
		]
		switch event [
			fetch [
				switch :value [@stop [options/debug/active?: yes] @go [options/debug/active?: no]]
				if paren? expr-stk/1 [remove expr-stk]
			]
			enter [
				unless empty? head expr-stk [
					append expr-stk index? expr-stk
					expr-stk: tail expr-stk
				]
			]
			exit [
				either head? expr-stk [clear expr-stk][
					if paren? expr-stk/1 [set/any 'value expr-stk/1/1]
					idx: first pos: find/reverse tail expr-stk integer!
					clear pos
					expr-stk: at head expr-stk idx
					do store
				]
			]
			open [
				append/only expr-stk reduce [:value]
			]
			push [
				either find [set-word! set-path!] type?/word :value [
					append/only expr-stk reduce [:value]
				][
					do store
				]
			]
			prolog [append/only fun-stk last expr-stk]
			epilog [unless empty? fun-stk [take/last fun-stk]]
			set 
			return [
				take/last expr-stk
				do store
			]
			error [options/debug/active?: yes]			;-- forces debug console activation
			init end  [
				clear fun-stk
				clear expr-stk: head expr-stk
				indent: 0
				sch: system/console/history
				if event = 'init [hist-length: length? sch]
				if event = 'end [
					options/debug/active?: no
					remove/part sch (length? sch) - hist-length
				]
			]
		]
		if all [
			options/debug/active?
			not find [init end enter exit prolog epilog expr] event
		][
			if event = 'fetch [event: 'eval]
			prin out: rejoin ["-----> " uppercase mold event space]
			if event = 'set [
				append out set-ref: rejoin [ref space]
				prin set-ref
			]
			limit: calc-max (length? out) + 1
			print either all [any-function? :value not find [set return push] event][
				prin mold/part/flat :ref limit
				rejoin [" (" mold type? :value #")"]
			][
				mold/part/flat :value limit
			]
			if :code [print ["Input:" mold/only/part/flat skip :code offset calc-max 8]]
			
			unless empty? watching			[show-watching]
			if options/debug/show-parents?	[show-parents event]
			if options/debug/show-stack?	[show-stack]
			
			do-command event
			if event = 'error [options/debug/active?: no]
		]
	]
	
	dumper: function [
		event  [word!]
		code   [any-block! none!]
		offset [integer!]
		value  [any-type!]
		ref	   [any-type!]
		frame  [pair!]
	][
		print [uppercase form event offset mold/part/flat :ref 30 mold/part/flat :value 30 frame]
	]
	
	tracer: function [
		event  [word!]
		code   [any-block! none!]
		offset [integer!]
		value  [any-type!]
		ref	   [any-type!]
		frame  [pair!]
		/extern indent
	][
		[init end open push call prolog epilog set return error catch throw] ;-- request only those events
		
		either find [init end] event [
			if event = 'end [prin lf]
			indent: 0
		][
			if event = 'return [indent: indent - 1]
			if any-function? :value [value: type? :value]

			out: clear ""
			append out "-> "
			if options/trace/indent? [append/dup out space indent]
			append out uppercase mold event
			ref: either ref [rejoin ["  (" ref #")"]][""]
			append out space
			append out mold/part/flat :value calc-max (length? out) + length? ref
			append out ref
			print out

			if event = 'open [indent: indent + 1]
		]
	]
	
	profiler: function [
		event  [word!]
		code   [any-block! none!]
		offset [integer!]
		value  [any-type!]
		ref	   [any-type!]
		frame  [pair!]
	][
		[init call return prolog epilog]				;-- request only those events
		anon: [0]
		
		switch event [
			prolog [									;-- entering a function!
				time: now/precise
				poke skip tail fun-stk -2 1 time		;-- update start-time
			]
			epilog [									;-- exiting a function!
				poke back tail fun-stk 1 now/precise	;-- update start-time
			]
			call   [
				if all [typeset? opt: options/profile/types find opt type? :value][
					if any-function? :ref [ref: append copy <anon> anon/1: anon/1 + 1]
					either pos: find/only/skip profiling ref 3 [
						pos/2: pos/2 + 1
					][
						repend profiling [ref 1 0]
					]
					repend fun-stk [ref now/precise none] ;-- [name start-time end-time]
				]
			]
			return [
				time: now/precise
				unless empty? fun-stk [
					entry: skip tail fun-stk -3
					pos: find/only/skip profiling first entry 3
					pos/3: pos/3 + difference any [entry/3 time] entry/2
					clear entry
				]
			]
			init [
				clear profiling
				clear fun-stk
			]
		]
	]
	
	do-handler: func [code [any-type!] handler [function!]][
		either find [file! url!] type?/word :code [
			do-file code :handler						;-- delay handler triggering once resource is acquired
		][
			do/trace :code :handler
		]
	]
	
	set 'profile function [
		"Profile the argument code, counting calls and their cumulative duration, then print a report"
		code [any-type!] "Code to profile"
		/by
			cat [word!]	 "Sort by: 'name, 'count, 'time"
	][
		saved: values-of options/profile
		options/profile/sort-by: any [cat 'count]
		
		set/any 'res do-handler :code :profiler
		if value? 'res [print ["==" mold/part :res calc-max 2 lf]]
		
		by: select [name 1 count 2 time 3] options/profile/sort-by
		either by = 1 [
			sort/skip/compare profiling 3 by			;-- sort in alphabetical order
		][
			sort/skip/reverse/compare profiling 3 by	;-- sort count/time in decreasing order
		]
		rank: 1
		foreach [name cnt duration] profiling [			;-- generate report
			if unset? name [name: "<anonymous>"]
			print [pad append copy "#" rank 4 pad name 16 #"|" pad cnt 10 #"|" pad duration 10]
			rank: rank + 1
		]
		set options/profile saved
		()
	]
	
	set 'trace function [
		"Runs argument code and prints an evaluation trace; also turns on/off tracing"
		code [any-type!] "Code to trace or tracing mode (logic!)"
		/raw			 "Switch to raw interpreter events tracing"
	][
		either logic? :code [
			#system [
				use [bool [red-logic!]][
					bool: as red-logic! ~code			;@@ implement a clean way to access locals from R/S code
					assert TYPE_OF(bool) = TYPE_LOGIC
					interpreter/tracing?: bool/value and interpreter/trace?
				]
			]
		][
			do-handler :code either raw [:dumper][:tracer]
		]
	]
	
	set 'debug func [
		"Runs argument code through an interactive debugger"
		code [any-type!] "Code to debug"
		/later			 "Enters the interactive debugger later, on reading @stop value"
	][
		saved: values-of options/debug
		options/debug/active?: not later
		do-handler :code :debugger
		set options/debug saved
		()
	]
]
