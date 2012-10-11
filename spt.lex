
-title lex:  translate minimal to lexemes (tokens)
-stitl initialization
* copyright 1987-2012 Robert B. K. Dewar and Mark Emmer.
* copyright 2012 David Shields
* 
* this file is part of macro spitbol.
* 
*     macro spitbol is free software: you can redistribute it and/or modify
*     it under the terms of the gnu general public license as published by
*     the free software foundation, either version 3 of the license, or
*     (at your option) any later version.
* 
*     macro spitbol is distributed in the hope that it will be useful,
*     but without any warranty; without even the implied warranty of
*     merchantability or fitness for a particular purpose.  see the
*     gnu general public license for more details.
* 
*     you should have received a copy of the gnu general public license
*     along with macro spitbol.  if not, see <http://www.gnu.org/licenses/>.
*
*
*	usage:
*
*	spitbol -u "infile<sep>condfile<sep>outfile" lex
*
*	where:
*	 infile    - minimal file name, less .min extension
*	 condfiile - conditional file name, less .cnd extension
*	 outfile   - output file name, less .lex extension.
*		     default is infile.lex.
*	 <sep>	   - ; or :
*
*	note: <sep>outfile component is optional.
*
*  this program takes minimal statements and parses them up into
*  a stream of lexemes (tokens). it performs equ * substitution and
*  conditional assembly.
*
*  it is based on earlier translators written by david shields,
*  steve duff and robert goldberg.
*
        version = 'v1.14'

*  generate dump if abnormal termination
	&dump = 1
-eject
*  keyword initialization

        &anchor = 1;    &stlimit = -1;  &trim   = 1
*  useful constants

	minlets = 'abcdefghijklmnopqrstuvwxy_'
	nos     = '0123456789'
	p.nos	= span(nos) rpos(0)
	p.exp	= 'e' any('+-') span(nos)
	p.real	= span(nos) '.' (span(nos) | null) (p.exp | null) rpos(0)
	tab	= char(9)

*  argform classifies arguments
	define('argform(arg)')

*  argtype checks argument types
	define('argtype(op,typ)')

*  crack parses stmt into a stmt data plex and returns it.
*  stmt is the common data plex used to hold the components of
*  a minimal statement during processing.
*  it fails if there is a syntax error.
*
	define('crack(line)operands,operand,char')

*
*  error is used to report an error for current statement
*
	define('error(text)')

*  labenter enters non-null label in labtab
	define('labenter()tlab')

*  outstmt is used to send a target statement to the target code
*  output file (outfile <=> lu2)
*
	define('outstmt(label,opcode,op1,op2,op3,comment)t,stmtout')

*  rdline is called to return the next non-comment line from
*  the minimal input file (infile <=> lu1).   note that it will
*  not fail on eof, but it will return a minimal end statement
*
	define('rdline()first,last')
* 	conditional assembly initialization

	define('tblini(str)pos,cnt,index,val,lastval')
*  catab is the transfer vector for routing control to generators
*  for conditional assembly directives.
*
	catab = table(11,,.badop)
	catab['.def'] = .defop; catab['.undef'] = .undefop
	catab['.if']   = .ifop; catab['.then']  = .thenop
	catab['.else']  = .elseop; catab['.fi']    = .fiop

*  symtbl tracks defined conditional symbols.  (undefined symbols
*  are assigned null values in symtbl.)
*
       symtbl      = table( 11 )
*
*  statestk maintains all state information while processing conditional
*  statements.  level indexes the top entry.  another variable, top,
*  has a copy of savestk[level].
*
       statestk    = array( 30 )
       level       = 0
       top         =
*
*  each state entry in statestk contains state information about
*  the processing for each active .if.  the state is maintained
*  as 2 fields:
*
*      result    the result of the .if expression evaluation-
*                true, false, or bypass
*
*      mode      whether processing then or else portion of .if
*
       data( 'state(result,mode)' )
       false    = 0
       true     = 1
       bypass   = 2
       else     = 0
       then     = 1
*
*  processrec is indexed by the current result and mode to determine
*  whether or not a statement should be processed and written to the
*  output file.
*
       processrec    = array( false ':' bypass ',' else ':' then,0 )
       processrec[true,then]  = 1
       processrec[false,else] = 1
*
*  p.condasm breaks up conditional assembly directives.
*
       sep      = ' '
       p.condasm      = ( break(sep) | rem ) . condcmd
.	          ( span(sep) | '' )
.	          ( break(sep) | rem ) . condvar
*
*
	p.argskel1 = fence(break(',') | rem) $ argthis *differ(argthis)
	p.argskel2 = len(1) fence(break(',') | rem) $ argthis *differ(argthis)

*  ityptab is table mapping from common operands to gross type

	ityptab = table(21)
	ityptab['0'] = 1; ityptab['1'] = 1; ityptab['wa'] = 8
	ityptab['wb'] = 8; ityptab['wc'] = 8; ityptab['xl'] = 7
	ityptab['xr'] = 7; ityptab['xs'] = 7; ityptab['xt'] = 7
	ityptab['(xl)'] = 9; ityptab['(xr)'] = 9; ityptab['(xs)'] = 9
	ityptab['(xt)'] = 9; ityptab['-(xl)'] = 11; ityptab['-(xr)'] = 11
	ityptab['-(xs)'] = 11; ityptab['-(xt)'] = 11;
	ityptab['(xl)+'] = 10;	ityptab['(xr)+'] = 10;
	ityptab['(xs)+'] = 10; ityptab['(xt)+'] = 10

*  opformtab is table mapping general op formats to row index for
*  validform array.
	opformtab = tblini(
+	'val[1]reg[2]opc[3]ops[4]opw[5]opn[6]opv[7]addr[8]'
+	'x[9]w[10]plbl[11](x)[12]integer[13]real[14]'
+	'dtext[15]eqop[16]int[17]pnam[18]')

*  validform is array that validates general op formats (opv, etc).
*  the first index is named type val=1 reg=2 opc=3 ops=4 opw=5
*  opn=6 opv=7 addr=8 x=9 w=10 plbl=11 (x)=12 integer=13 real=14
*  dtext=15 eqop=16 int=17 pnam=18
*  the second argument is gross type 01=int 02=dlbl ... 27=dtext
*  the entry [i,j] is nonzero is gross type j is valid for named
*  type i.
   validform = array('18,27',0)
   validform[1,1] = 1
   validform[1,2] = 1
   validform[2,7] = 1
   validform[2,8] = 1
   validform[3,9] = 1
   validform[3,10] = 1
   validform[3,11] = 1
   validform[4,3] = 1
   validform[4,4] = 1
   validform[4,9] = 1
   validform[4,12] = 1
   validform[4,13] = 1
   validform[4,14] = 1
   validform[4,15] = 1
   validform[5,3] = 1
   validform[5,4] = 1
   validform[5,8] = 1
   validform[5,9] = 1
   validform[5,10] = 1
   validform[5,11] = 1
   validform[5,12] = 1
   validform[5,13] = 1
   validform[5,14] = 1
   validform[5,15] = 1
   validform[6,3] = 1
   validform[6,4] = 1
   validform[6,7] = 1
   validform[6,8] = 1
   validform[6,9] = 1
   validform[6,10] = 1
   validform[6,11] = 1
   validform[6,12] = 1
   validform[6,13] = 1
   validform[6,14] = 1
   validform[6,15] = 1
   validform[7,3] = 1
   validform[7,4] = 1
   validform[7,7] = 1
   validform[7,8] = 1
   validform[7,9] = 1
   validform[7,10] = 1
   validform[7,11] = 1
   validform[7,12] = 1
   validform[7,13] = 1
   validform[7,14] = 1
   validform[7,15] = 1
   validform[7,18] = 1
   validform[7,19] = 1
   validform[7,20] = 1
   validform[7,21] = 1
   validform[7,22] = 1
   validform[8,1] = 1
   validform[8,2] = 1
   validform[8,3] = 1
   validform[8,4] = 1
   validform[8,5] = 1
   validform[8,6] = 1
   validform[9,7] = 1
   validform[10,8] = 1
   validform[11,6] = 1
   validform[12,9] = 1
   validform[13,16] = 1
   validform[14,17] = 1
   validform[15,27] = 1
   validform[16,24] = 1
   validform[17,1] = 1
   validform[18,6] = 1
   validform[18,23] = 1
*
*  zero the counts
*
	labcnt = noutlines = nlines = nstmts = ntarget = nerrors = 0
*
*  p.minlabel is a pattern matching a valid minimal source label.
*
	p.minlabel = any(minlets) any(minlets) any(minlets nos)
.	           any(minlets nos) any(minlets nos)
*
*  p.csparse parses out the components of the input line in stmt,
*  and puts them into the locals: label, opcode, operands, comment
*
	p.csparse = (((p.minlabel . label) | ('     '  '' . label)) '  '
.	  len(3) . opcode
.	  (('  ' (break(' ') | rtab(0)) . operands
.	      (span(' ') | '') rtab(0) . comment)  |
.	      (rpos(0) . operands . comment)))  |
.	     ('.'  '' . label  mincond . opcode
.	       ((tab(7)  '.'  len(4) . operands) | (rpos(0) . operands))
.	           '' . comment)
*
*  p.csoperand breaks out the next operand in the operands string.
*
	p.csoperand = (break(',') . operand  ',')  |
.			((len(1) rtab(0)) . operand)
*
*  p.csdtc is a pattern that handles the special case of the
*  minimal dtc op
*
	p.csdtc   = ((p.minlabel . label)  |  ('     '  '' . label))
.	          len(7) (len(1) $ char  break(*char)  len(1)) . operand
.	          (span(' ') | '')  rtab(0) . comment
*
*  p.equ.rip is a pattern that parses out the components of an equ
*  expression.
*
	p.equ.rip  = ( span(nos) . num1 | p.minlabel . sym1 )
.		   ( any('+-') . oprtr | '' )
.		   ( span(nos) . num2 | p.minlabel . sym2 | '' )
.		   rpos(0)

*  optab is a table that maps opcodes into their argument
*  types and is used for argument checking and processing.
	optab = tblini(
. 'flc[w]'
. 'add[opn,opv]adi[ops]adr[ops]anb[w,opw]aov[opn,opv,plbl]atn[none]'
. 'bod[opn,plbl]bev[opn,plbl]'
. 'bct[w,plbl]beq[opn,opv,plbl]bge[opn,opv,plbl]bgt[opn,opv,plbl]'
. 'bhi[opn,opv,plbl]ble[opn,opv,plbl]blo[opn,opv,plbl]'
. 'blt[opn,opv,plbl]bne[opn,opv,plbl]bnz[opn,plbl]brn[plbl]'
. 'bri[opn]bsw[x,val,*plbl bsw]btw[reg]'
. 'bze[opn,plbl]ceq[ops,ops,plbl]'
. 'chk[none]chp[none]cmb[w]cmc[plbl,plbl]cne[ops,ops,plbl]cos[none]csc[x]ctb[w,val]'
. 'ctw[w,val]cvd[none]cvm[plbl]dac[addr]dbc[val]dca[opn]dcv[opn]'
. 'def[def]dic[integer]drc[real]dtc[dtext]dvi[ops]dvr[ops]ejc[none]'
. 'else[else]end[none end]enp[none]ent[*val ent]equ[eqop equ]'
. 'erb[int,text erb]err[int,text err]esw[none esw]etx[none]exi[*int]exp[int]fi[fi]'
. 'ica[opn]icp[none]icv[opn]ieq[plbl]if[if]iff[val,plbl iff]ige[plbl]'
. 'igt[plbl]ile[plbl]ilt[plbl]ine[plbl]ino[plbl]inp[ptyp,int inp]'
. 'inr[none]iov[plbl]itr[none]jsr[pnam]lch[reg,opc]lct[w,opv]lcp[reg]'
. 'lcw[reg]ldi[ops]ldr[ops]lei[x]lnf[none]lsh[w,val]lsx[w,(x)]mcb[none]'
. 'mfi[opn,*plbl]mli[ops]mlr[ops]mnz[opn]mov[opn,opv]mti[opn]'
. 'mvc[none]mvw[none]mwb[none]ngi[none]ngr[none]nzb[w,plbl]'
. 'orb[w,opw]plc[x,*opv]ppm[*plbl]prc[ptyp,val prc]psc[x,*opv]req[plbl]'
. 'rge[plbl]rgt[plbl]rle[plbl]rlt[plbl]rmi[ops]rne[plbl]rno[plbl]'
. 'rov[plbl]rsh[w,val]rsx[w,(x)]rti[*plbl]rtn[none]sbi[ops]'
. 'sbr[ops]sch[reg,opc]scp[reg]sec[none sec]sin[none]sqr[none]ssl[opw]sss[opw]'
. 'sti[ops]str[ops]sub[opn,opv]tan[none]then[then]trc[none]ttl[none ttl]'
. 'undef[undef]wtb[reg]xob[w,opw]zer[opn]zgb[opn]zrb[w,plbl]' )


*  prctab is table of procedures declared in inp that is used to
*  check for consistency of inp/prc statements.
*
	prctab = table(60)
*
*  equates is used by g.equ and .  it contains a directory of
*  all labels that were defined by equ instructions.
*
	equates = table(257)

*  labtab is a table that maps each label to the section in which
*  it is defined, except labels defined in the definitions section
*  (section 2).

	labtab = table(150,150)

*  bsw is a flag that indicates whether or not a bsw...esw range
*  is being processed.
*
	bsw	= 0
*
*
*  comment.block is set when inside multi-line comment.
*  A multi-line comment begins (ends)  with '{' ('}') in the
*  first column, respectivey. 
*
	comment.block = 

-stitl machine-dependent initializations
*  following values for 68000, a 32-bit machine
*  some definitions appear in limited form in cod.spt
*
       g.equ.defs = tblini(
. 'cfp_a[256]'
. 'cfp_b[4]'
. 'cfp_c[4]'
. 'cfp_f[8]'
. 'cfp_i[1]'
. 'cfp_l[4294967295]'
. 'cfp_m[2147483647]'
. 'cfp_n[32]'
. 'cfp_u[128]'
. 'nstmx[10]'
. 'cfp_r[2]'
. 'cfp_s[9]'
. 'cfp_x[3]'
. 'e_srs[100]'
. 'e_sts[1000]'
. 'e_cbs[500]'
. 'e_hnb[257]'
. 'e_hnw[6]'
. 'e_fsp[15]'
. 'e_sed[25]'
. 'ch_la[065]ch_lb[066]ch_lc[067]ch_ld[068]ch_le[069]ch_lf[070]'
. 'ch_lg[071]ch_lh[072]ch_li[073]ch_lj[074]ch_lk[075]ch_ll[076]'
. 'ch_lm[077]ch_ln[078]ch_lo[079]ch_lp[080]ch_lq[081]ch_lr[082]'
. 'ch_ls[083]ch_lt[084]ch_lu[085]ch_lv[086]ch_lw[087]ch_lx[088]'
. 'ch_ly[089]ch_l_[090]'
. 'ch_d0[048]ch_d1[049]ch_d2[050]ch_d3[051]ch_d4[052]ch_d5[053]'
. 'ch_d6[054]ch_d7[055]ch_d8[056]ch_d9[057]ch__a[097]ch__b[098]'
. 'ch__c[099]ch__d[100]ch__e[101]ch__f[102]ch__g[103]ch__h[104]'
. 'ch__i[105]ch__j[106]ch__k[107]ch__l[108]ch__m[109]ch__n[110]'
. 'ch__o[111]ch__p[112]ch__q[113]ch__r[114]ch__s[115]ch__t[116]'
. 'ch__u[117]ch__v[118]ch__w[119]ch__x[120]ch__y[121]ch___[122]'
. 'ch_am[038]ch_as[042]ch_at[064]ch_bb[060]ch_bl[032]ch_br[124]'
. 'ch_cl[058]ch_cm[044]ch_dl[036]ch_dt[046]ch_dq[034]ch_eq[061]'
. 'ch_ex[033]ch_mn[045]ch_nm[035]ch_nt[126]ch_pc[037]ch_pl[043]'
. 'ch_pp[040]ch_rb[062]ch_rp[041]ch_qu[063]ch_sl[047]ch_sm[059]'
. 'ch_sq[039]ch_un[095]ch_ob[091]ch_cb[093]ch_ht[009]ch_vt[011]'
. 'ch_ey[094]iodel[032]' )
*
-stitl main program
*  here follows the driver code for the "main" program.

*
*  loop until program exits via g.end
*
*  dostmt is invoked to initiate processing of the next line from
*  rdline.
*  after doing this, dostmt branches to the generator routine indicated
*  for this opcode if there is one.
*  the generators all have entry points beginning
*  with "g.", and can be considered a logical extension of the
*  dostmt routine.  the generators have the choice of branching back
*  to dsgen to cause the thisstmt plex to be sent to outstmt, or
*  or branching to dsout, in which case the generator must output
*  all needed code itself.
*
*  the generators are listed in a separate section below.
	trandate = date()
*	exit(-2)

*  start execution
*
*	reads for xxx.min, writes to xxx.lex, where xxx is a command line parameter.
*	the command line parameter may optionally be expressed as xxx;yyy, where
*	yyy.cnd is the name of a file containing .defs to override those in
*	file xxx.min.
*
*  get file name
*
*
*  default the parameter string if none present
*
	parms = (differ(host(0)) host(0), "v37:dos")
*
*  get file name
*
	parms ? break(';:') . parms len(1) (break(';:') | rem) . filenamc
.		(len(1) | null) rem . filenamo
        output = ident(parms) "need file name (.min)" :s(end)

	filenami = parms '.min'
        output = rpad('input minimal file:',24)  filenami
	filenamo = (ident(filenamo) parms, filenamo) '.lex'
        output = rpad('output lexeme file:',24)	 filenamo
*   flcflag  = replace( input,'y','y' )
	flcflag = 'n'
	flcflag = 'y'
*  output = 'full line comments passed to lexeme file? ' flcflag
*
*  no page ejects without full line comments
*
*   output = differ(flcflag,'n')
*   ejcflag  = replace( (differ(flcflag,'n') input, 'n'),'y','y' )
	ejcflag = 'n'
	ejcflag = 'y'
*  output = 'ejcs passed to lexeme file? ' ejcflag
*
*  associate input file to lu1.  if a conditional file was specified,
*  read it first.
*
	input(.infile,1,filenami)	:s(main1)
        output = "cannot open minimal file: " filenami        :(end)
*
*
*  associate output file
*
main1	output(.outfile,2,filenamo)		:s(main2)
        output = "cannot open lex file: " filenamo  :(end)
main2

*  patterns used by dostmt
	p.opsk1 = (break(' ') | rem) . argskel

  :(dsout)
  &trace = 4000
  &ftrace = 4000
*  &profile = 1
dsout
dostmt	thisline = rdline()
	crack(thisline)            		:f(dsout)
	differ(label) labenter()
	argerrs = 0

	opskel = optab[opcode]			:f(ds01)
	ident(opskel) error("opcode not known")
	opskel p.opsk1 =
	ident(argskel,'none')			:s(dos10)

*  here if arguments to verify
dos01	ident(argskel)				:s(dos05)
	argskel p.argskel1 =
*  accept null argument if this argument optional
	argthis '*' ident(op1)			:s(dos05)
	typ1 = argtype(op1,argthis)
	argerrs = eq(typ1) argerrs + 1
	ident(argskel)				:s(dos05)
	argskel p.argskel2 =
	argthis '*' ident(op2)			:s(dos05)
	typ2 = argtype(op2,argthis)
	argerrs = eq(typ2) argerrs + 1
	ident(argskel)				:s(dos05)
	argskel p.argskel2 =
	argthis '*' ident(op3)			:s(dos05)
	typ3 = argtype(op3,argthis)		:(dos05)
	argerrs = eq(typ3) argerrs + 1
dos10
dos05
	gt(argerrs) error('arg type not known')
*  here if an argument type not recognized
	opskel ' ' =				:f(dsgen)
*  here if post-processing required
	            :($('g.' opskel))
*
*  get generator entry point (less "g." prefix)
*
  :(g.h)
*  here if bad opcode
ds01	error('bad op-code')			:(dsout)

*  generate lexemes.
*
ds.typerr
	error('operand type zero')		:(dsout)
dsgen   outstmt(label,opcode,op1,op2,op3,comment) :(dsout)
-stitl argform(arg)
argform
	argform = 0
*  determine operand format type as follows
	ident(t = ityptab[arg])			:s(argform1)
*  ityptab has table of cases for types 07,08,09,10,11
*  if entry in this table, type immediately available:
*  w reg is 08 x reg is 07 (x)+ is 10 -(x) is 11 (x) is 09
	argform = t				:(return)
argform1
	arg p.nos				:s(argform.int)
	arg '='					:s(argform.eq)
	arg '*'					:s(argform.star)
	arg any('+-')				:s(argform.snum)
	arg break('(')				:s(argform.index)
*  here if the only possibility remaining is a name which must be lbl
*  if the label not yet known, assume it is a plbl
	ident(t = labtab[arg])			:s(argform.plbl)
	argform = t				:(return)
argform.plbl labtab[arg] = 6
	argform = 6				:(return)
argform.eq
	arg len(1) rem . itypa
	itypa = labtab[itypa]
	argform = (eq(itypa,2) 18, eq(itypa,6) 22,
.	gt(itypa,2) itypa + 17) :s(return)
*  if =lbl and lbl not known, it must be elbl
	argform = 22
	labtab[itypa] = 5			:(return)
argform.star
	arg len(1) rem . t			:f(return)
	eq(labtab[t],2)				:f(return)
	argform = 19				:(return)
argform.int	argform = 1			:(return)
argform.snum	arg len(1) p.nos		:f(argform.sreal)
		argform = 16			:(return)
argform.sreal	arg len(1) p.real		:f(return)
		argform = 17			:(return)
argform.index	arg break('(') . t '(x' any('lrst') ')' rpos(0)
.						:f(return)
	t p.nos					:f(argform.index1)
*  here if int(x)
	argform = 12				:(return)
argform.index1
	ident(t = labtab[t])			:s(return)
	argform = (eq(t,2) 13, eq(t,3) 15, eq(t,4) 14)	:(return)
-stitl argtype(op,typ)
*  this module checks operand types of current operation,
*  prefixing each operand with type code as given in
*  minimal definition.
*  initially classify as one of following:
*  01=int 02=dlbl  03=name 07=x  08=w  09=(x) 10=(x)+  11=-(x)
*  12=int(x)  13=dlbl(x)  14=name(x)  16=signed-integer
*  17=real  18==dlbl  19=*dlbl 20==name  23=pnam 24=eqop
*  25=ptyp  26=text  27=dtext
argtype
	argtype = 0
*  typ may have initial'*' indicating argument optional. this
*  code reached only if argument not null, so remove the '*'.
	typ '*' =

	ident(typ,'text') 			:s(arg.text)
	ident(typ,'dtext') 			:s(arg.dtext)
	ident(typ,'ptyp')			:s(arg.ptyp)
	ident(typ,'eqop')			:s(arg.eqop)
	itype = argform(op)
	opform = opformtab<typ>
	argtype = ne(validform<+opform,itype>) itype	:(return)
*	argtype = itype 			:(return)

arg.text argtype = 26 				:(return)
arg.dtext argtype = 27				:(return)
arg.ptyp op any('rne')				:f(return)
	argtype = 25				:(return)
arg.eqop
	op1 = ident(op,'*')
.			g.equ.defs[label]
	argtype = 24				:(return)

*
-stitl crack(line)operands,operand,char
*  crack is called to create a stmt plex containing the various
*  entrails of the minimal source statement in line.  for
*  conditional assembly ops, the opcode is the op, and op1
*  is the symbol.  note that dtc is handled as a special case to
*  assure that the decomposition is correct.
*
*  crack will print an error and fail if a syntax error occurs.
*
crack   nstmts  = nstmts + 1
	line    p.csparse			:f(cs03)
	op1 = op2 = op3 = typ1 = typ2 = typ3 =
	ident(opcode,'dtc')			:s(cs02)
*
*  now pick out operands until none left
*
	operands  p.csoperand = 		:f(cs01)
	op1 = operand
	operands  p.csoperand = 		:f(cs01)
	op2 = operand
	operands  p.csoperand			:f(cs01)
	op3 = operand
cs01	:(return)
*
*  dtc - special case
*
cs02	line	p.csdtc				:f(cs03)
	op1 = operand
						:(cs01)
*
*  here on syntax error
*
cs03	error('source line syntax error')	:(freturn)
-stitl error(text)
*  this module handles reporting of errors with the offending
*  statement text in thisline.  comments explaining
*  the error are written to the listing (including error chain), and
*  the appropriate counts are updated.
*
error
	output = 'error ' text '  at line ' nlines ' ' thisline
	outfile = '* *???* ' thisline
	outfile = '*       ' text
.	          (ident(lasterror),'. last error was line ' lasterror)
	lasterror = noutlines
	noutlines = noutlines + 2
	nerrors = nerrors + 1
	&dump = 2
						:(end)
*					:(dsout)
-stitl labenter()tlab
*  labenter is called to make entry in labtab for a label
*  current classification is 3 for wlbl, 4 for clbl and 5 for
*  other labels
labenter
	ident(label)				:s(return)
	labtab[label] = (eq(sectnow,2) 2, eq(sectnow,3) 4,
.	eq(sectnow,4) 3 , gt(sectnow,4)  6) 	:(return)
-stitl outstmt(label,opcode,op1,op2,op3,comment)t,stmtout
*
outstmt
*
*  send text to outfile
*
	outfile = '|' label '|' opcode '|'
.	(ident(typ1), typ1 ',') op1 '|'
.	(ident(typ2), typ2 ',') op2 '|'
.	(ident(typ3), typ3 ',') op3 '|' comment
.	'|' nlines
	ntarget = ntarget + 1
	noutlines = noutlines + 1
.						:(return)
-stitl rdline()
*  this routine returns the next statement line in the input file
*  to the caller.  it never fails.  if there is no more input,
*  then a minimal end statement is returned.
*  comments are passed through to the output file directly.
*  conditional assembly is performed here.
*
*  lines beginning with ">" are treated as snobol4 statements
*  and immediately executed.
*
rdline	rdline = infile				:f(rdline.5)
	nlines  = nlines + 1
*	output = 'rdline ' nlines ' ' rdline ';'

*  blank line is comment

	rdline = ident(rdline) '*'


*  transfer control to appropriate conditional assembly
*  directive generator or other statement generator.
*
	leq(substr(rdline,1,1), '.')			:s(rdline.2)
rdline.1	eq( level )				:s(rdline.3)
	eq( processrec[result(top),mode(top)] )	:s(rdline)f(rdline.3)
rdline.2
	rdline ? p.condasm			:s( $catab[condcmd] )

rdline.3
   	first = substr(rdline,1,1)
   	comment.block = leq(first, '{') 1
   	comment.block = leq(first, '}') 0
* output = lpad(nlines,5) ' ' comment.block ' ' rdline
*  continue on if inside comment block
	eq(comment.block,1)			:s(rdline)
	rdline any('*{}')			:f(rdline.4)
	rdline len(1) . first rem . last = '*' last

*  only print comment if requested.
 
 	outfile = ident(flcflag,'y') rdline	:f(rdline)

rdline.out
	outfile = rdline
	noutlines = noutlines + 1		:(rdline)



rdline.4 leq(substr(rdline,1,1),'>')		:f(return)

*
*  here with snobol4 line to execute
*
	c = code(substr( rdline, 2 ) "; :(rdline)") :s<c>
        output = "error compiling snobol4 statement"
  						:(rdline.5)
*
*  here on eof.  
*
rdline.5	

*	output = 'at rdline.5'
	rdline = '       end'			:(rdline.4)

*  syntax error handler.
*
synerr output = incnt '(syntax error):' rdline            :(rdline)
*
*  process define
*
defop  
	ident( condvar )				:s(synerr)
       differ( ignore_defs )			:s(rdline)
       eq( level )				:s(defok)
       eq( processrec[result(top),mode(top)] )	:s(rdline)
defok  symtbl[condvar] = 1			:(rdline)
*
*  process undefine
*
undefop
       ident( condvar )				:s(synerr)
       eq( level )				:s(undok)
       eq( processrec[result(top),mode(top)] )	:s(rdline)
undok  symtbl[condvar] =			:(rdline)
*
*  process if
*
ifop   
	ident( condvar )				:s(synerr)
       eq( level )				:s(ifok)
*
*  here for .if encountered during bypass state.
*
       ne( processrec[result(top),mode(top)] )  :s(ifok)
       level    = level + 1
       top      = statestk[level] = state(bypass,then)    :(rdline)
*
*  here for .if to be processed normally.
*
ifok   level    = level + 1
       top      = statestk[level] = state(
.	             ( differ( symtbl[condvar] ) true,false ),
.	             then )			:(rdline)
*
*  process .then
*
thenop	
	differ(condvar)				:s(synerr)
	eq(level)				:s(synerr)f(rdline)
*
*  process .else
*
elseop	
	differ(condvar)				:s(synerr)
	mode(top) = ne( level ) else		:s(rdline)f(synerr)
*
*  process .fi
*
fiop	
	differ(condvar)				:s(synerr)
	level = ne( level ) level - 1		:f(synerr)
	top   = ( ne( level ) statestk[level],'' )     :(rdline)
*
*  process statements other than conditional directives.
*
-stitl	tblini(str)pos,cnt,index,val,lastval
*  this routine is called to initialize a table from a string of
*  index/value pairs.
*
tblini	pos     = 0
*
*  count the number of "[" symbols to get an assessment of the table
*  size we need.
*
tin01   str     (tab(*pos) break('[') break(']') *?(cnt = cnt + 1) @pos)
.	                              	:s(tin01)
*
*  allocate the table, and then fill it. note that a small memory
*  optimisation is attempted here by trying to re-use the previous
*  value string if it is the same as the present one.
*
	tblini   = table(cnt)
tin02   str     (break('[') $ index len(1) break(']') $ val len(1)) =
.	                              	:f(return)
	val     = convert( val,'integer' )
	val     = ident(val,lastval) lastval
	lastval = val
	tblini[index] = val			:(tin02)
-stitl generators
*
*  bsw processing begins by building an array that can hold all
*  iff operands and comments.
*
g.bsw
*  save prior vms code in case needed
	ub = ( integer( op2 ) op2, equates[op2] )
	iffar = integer( ub )
.		array( '0:' ub - 1,'||' )	:f(g.bsw1)
	dplbl = op3
	bsw   = 1				:(dsgen)
g.bsw1	error("non-integer upper bound for bsw")

*
*  iff processing sets the iffar[] element to the current
*  value, plbl, and comment.
*
g.iff
	(eq( bsw ) error("iff without bsw"))
	ifftyp = ( integer(op1) '1', '2')
	iffval = ( integer( op1 ) op1, equates[op1] )
	iffar[iffval] = integer( iffval )
.		ifftyp ',' op1 '|' typ2 ',' op2 '|'  comment
.						:s(dsout)
	error("non-integer iff value")
*
*  in order to support translation of minimal operands and
*  bsw/iff/esw preprocessing, all equ expressions must be
* 	evaluated and kept in a symbol table.
*
g.equ
	equates[label] = ident(op1,'*')
.			g.equ.defs[label]	:s(dsgen)

	num1 = num2 = sym1 = sym2 = oprtr =
	op1 p.equ.rip				:f(g.equ2)
	num1    = differ(sym1) equates[sym1]
	num2    = differ(sym2) equates[sym2]
	val     = eval( num1 ' ' oprtr ' ' num2 )	:f(g.equ3)
g.equ1	equates[label] = val				:(dsgen)
g.equ2	error("equ operand syntax error")
g.equ3	error("equ evaluation failed: " num1 ' ' oprtr ' ' num2 ' "' op1 '"' )
*
*  esw processing generates an iff for every value in the
*  bsw range.
*
g.esw
	(eq(bsw) error("esw without bsw"))
	iffindx = 0
g.esw1	iffar[iffindx] break('|') $ val len(1)
.		break( '|' ) $ plbl len(1)
.		rem $ cmnt
.						:f(g.esw2)
	val = ident( val ) '1,' iffindx
	plbl = ident( plbl ) '6,' dplbl
	(ident(dplbl) ident(plbl) error("missing iff value: "
.		 val " without plbl in preceding bsw"))
	outstmt(,'iff',val,plbl,,cmnt)
	iffindx = iffindx + 1			:(g.esw1)
g.esw2  iffar =					:(dsgen)

*  end prints statistics on terminal then exits program
*
g.end   outstmt(,'end',,,,comment)
	(ne(level) error("unclosed if conditional clause"))
        output = rpad('lines read:',24)  		nlines 
        output = rpad('statements processed:',24) 	nstmts 
        output = rpad('lines written:', 24) 		ntarget 
        output = ne(nerrors) nerrors 'errors occurred: '
        output =
.	  differ(lasterror) 'the last error was in line ' lasterror
	&code   = ne(nerrors) 2001
*        output = collect() * 5 ' free bytes'
	t = convert(prctab,'array')		:f(g.end.2)
*  here if procedures declared by inp but not by prc
        output = 'procedures with inp, no prc'
	i = 1
g.end.1 output = t[i,1] ' ' t[i,2]            :f(g.end.2)
	i = i + 1				:(g.end.1)
g.end.2
						:(finis)
g.ent
*  note program entry labels
*	entfile = label ',' op1
	labtab[label] = 5			:(dsgen)
g.h						:(dsgen)

*  keep track of sec statements

g.sec	sectnow = sectnow + 1  		:(dsgen)
g.ttl
	thisline len(10) rem . t
	t span(' ') =
	outstmt(,'ttl','27,' t)			:(dsout)
g.erb
g.err	thisline break(',') len(1) rem . t
	outstmt(label,opcode,op1, t)		:(dsout)

g.inp
	ident(label) error('no label for inp')
	differ(t = prctab[label]) error('duplicate inp')
	prctab[label] = op1			:(dsgen)

g.prc
	ident(label) error('no label for prc')
	ident(t = prctab[label]) error('missing inp')
	differ(t,op1) error('inconsistent inp/prc')
	prctab[label] =				:(dsgen)
finis
	&dump = 0
end
