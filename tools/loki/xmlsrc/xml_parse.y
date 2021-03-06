%pure_parser
%{
  /****************************************************************************
   *                                                                          *
   *     Loki - Programs for genetic analysis of complex traits using MCMC    *
   *                                                                          *
   *                     Simon Heath - CNG, Evry                              *
   *                                                                          *
   *                         February 2003                                    *
   *                                                                          *
   * xml_parse.y:                                                             *
   *                                                                          *
   * Basic XML parser                                                         *
   *                                                                          *
   * Copyright (C) Simon C. Heath 2003                                        *
   * This is free software.  You can distribute it and/or modify it           *
   * under the terms of the Modified BSD license, see the file COPYING        *
   *                                                                          *
   ****************************************************************************/

#include <config.h>
#include <stdlib.h>
#include <string.h>
#ifdef USE_DMALLOC
#include <dmalloc.h>
#endif
#include <stdio.h>
#include <ctype.h>

#include "string_utils.h"
#include "xml.h"
#include "lk_malloc.h"
#include "y.tab.h"

#undef YYLSP_NEEDED
#undef YYLEX_PARAM

  static int xmllex(yystype *);
  static int xmlerror(char *);
  static FILE *xmlin;
  static int *line_no,col_pos,abt_flag;
  static args *make_arg(string *,string *);
  static void free_att_list(args *);
  static void check_start(string *,args *);
  static void check_end(string *,int);
  static void check_declaration(args *);
  static int check_ws(string *);
  static int check_dtd_tok(string *,char *);
  static XML_handler *call;
  
  typedef struct state {
    struct state *next;
    struct state *prev;
    string *name;
  } state;

  static state *curr_state,*free_state_list;
  static int pi_state,in_comment,element_state,attlist_state;

  %}

%union {
  string *str;
  args *arg;
  char c;
  int i;
}

%token END XMLTOK QCLOSE QOPEN DOCTYPE COMMENTSTART ELEMENT ENTITY ATTLIST NOTATION CDATASTART DOUBLEDASH
%token EMPTY ANY PCDATA REQUIRED IMPLIED FIXED CDATA ID IDREF IDREFS ENTITY ENTITIES NMTOKEN NMTOKENS
%token <c> LETTER DIGIT SQ DQ DASH DOT USCORE COLON CHAR OPEN CLOSE SLASH AMPERSAND EQ LSBRACK RSBRACK PERCENT SEMICOLON
%token <c> LBRACK RBRACK STAR PLUS COMMA QUERY BAR
%token <str> SPACE
  
%type <str> name att_value dtd_tok
%type <str> att_val1 att_val2 cdata start1 content1 comment_content pi_data
%type <c> chardata chardata1 attchar1 attchar2 attchar name_char name_char1
%type <arg> attribute att_list

%%
document: prolog element misc
;
prolog: xmldecl misc1
| xmldecl misc1 doctypedecl misc1
| misc1
;
misc1: /* Empty */
| misc2
;
misc2: misc
| misc2 misc
;
eq: EQ {}
| SPACE EQ {free_string($1);}
| SPACE EQ SPACE {free_string($1); free_string($3);}
| EQ SPACE {free_string($2);}
;
doctypedecl: dtd_start1 CLOSE {}
| dtd_start1 LSBRACK RSBRACK opt_space CLOSE
| dtd_start1 LSBRACK int_subset RSBRACK opt_space CLOSE
;
dtd_start1: dtd_start opt_space {}
| dtd_start SPACE dtd_tok SPACE att_value opt_space {if(!check_dtd_tok($3,"SYSTEM")) printf("System '%s'\n",get_cstring($5));}
| dtd_start SPACE dtd_tok SPACE att_value SPACE att_value opt_space {if(!check_dtd_tok($3,"PUBLIC")) printf("Public '%s' '%s'\n",get_cstring($5),get_cstring($7));}
;
dtd_start: DOCTYPE SPACE name {printf("DTD name %s\n",get_cstring($3));}
;
int_subset: int_subset1 {}
| int_subset int_subset1 {}
;
int_subset1: markupdecl {}
| declsep {}
;
declsep: pereference {}
| SPACE {}
;
pereference: PERCENT name SEMICOLON {}
;
markupdecl: ELEMENT SPACE name SPACE {element_state=1;} contentspec opt_space CLOSE {element_state=0;}
| ATTLIST SPACE name attdef opt_space CLOSE
| ATTLIST SPACE name opt_space CLOSE
| pi {}
| comment {}
;
attdef: SPACE name SPACE {attlist_state=1;} atttype SPACE {attlist_state=2;} defaultdecl {attlist_state=0;}
| attdef SPACE name SPACE {attlist_state=1;} atttype SPACE {attlist_state=2;} defaultdecl {attlist_state=0;}
;
atttype: CDATA {}
| ID {}
| IDREF {}
| IDREFS {}
| ENTITY {}
| ENTITIES {}
| NMTOKEN {}
| NMTOKENS {}
| enum_type {}
;
enum_type: LBRACK opt_space name enums opt_space RBRACK {}
| LBRACK opt_space name opt_space RBRACK {}
;
enums: opt_space BAR opt_space name {}
| enums opt_space BAR opt_space name {}
;
defaultdecl: REQUIRED {}
| IMPLIED {}
| FIXED SPACE att_value {}
| att_value {}
;
opt_star: /* EMPTY */
| STAR {}
;
contentspec: EMPTY {}
| ANY {}
| choice_seq opt_modif {}
| LBRACK opt_space PCDATA opt_space RBRACK opt_star {}
| LBRACK opt_space PCDATA mixed opt_space RBRACK STAR
;
mixed: opt_space BAR opt_space name {}
| mixed opt_space BAR opt_space name {}
;
opt_modif: /* EMPTY */
| PLUS {}
| STAR {}
| QUERY {}
;
choice_seq: LBRACK opt_space cp choice opt_space RBRACK {}
| LBRACK opt_space cp seq opt_space RBRACK {}
| LBRACK opt_space cp opt_space RBRACK {}
;
choice: opt_space BAR opt_space cp {}
| choice opt_space BAR opt_space cp {}
;
seq: opt_space COMMA opt_space cp {}
| seq opt_space COMMA opt_space cp {}
;
cp: name opt_modif {}
| choice_seq opt_modif {}
;
pi_start: QOPEN {pi_state=1;}
;
xmldecl: pi_start XMLTOK att_list opt_space QCLOSE {pi_state=0; check_declaration($3);}
;
pi: pi_start name SPACE pi_data QCLOSE {pi_state=0; free_string($3); if(call->pi) call->pi($2,$4); free_string($2); free_string($4); }
| pi_start name opt_space QCLOSE {pi_state=0; if(call->pi) call->pi($2,0); free_string($2); }
;  
pi_data: chardata1 {$$=add_to_string(0,$1);}
| SPACE
| pi_data chardata1 {$$=add_to_string($1,$2);}
| pi_data SPACE {$$=add_strings($1,$2);}
;
dtd_tok: LETTER {$$=add_to_string(0,$1);}
| dtd_tok LETTER {$$=add_to_string($1,$2);}
;
chardata1: chardata
| OPEN
| AMPERSAND
;
chardata: attchar
| SQ
| DQ
;
attchar: name_char
| CHAR
| LSBRACK
| RSBRACK
| SEMICOLON
| PERCENT
| CLOSE
| EQ
| SLASH
;
attchar1: attchar
| DQ
;
attchar2: attchar
| SQ
;
name_char: name_char1
| DASH
| DOT
;
name_char1: LETTER
| DIGIT
| USCORE
| COLON
;
name: name_char1 {$$=add_to_string(0,$1);}
| name name_char {$$=add_to_string($1,$2);}
;
misc: comment {}
| pi {}
| SPACE {free_string($1);}
;
comment_content: chardata1 {$$=add_to_string(0,$1);}
| SPACE
| comment_content chardata1 {$$=add_to_string($1,$2);}
| comment_content SPACE {$$=add_strings($1,$2);}
;
comment: COMMENTSTART {in_comment=1;} comment_content DOUBLEDASH CLOSE {in_comment=0; if(call->comment) call->comment($3); free_string($3);}
;
element: empty_elem
| start_tag end_tag
| start_tag content end_tag
;
start1: OPEN name {$$=$2;}
;
start_tag: start1 att_list CLOSE {check_start($1,$2); }
| start1 opt_space CLOSE {check_start($1,0); }
;
att_list: attribute
| att_list attribute {$2->next=$1; $$=$2;}
;
attribute: SPACE name eq att_value {free_string($1); $$=make_arg($2,$4);}
;
att_value: SQ att_val1 SQ {$$=$2;}
| DQ att_val2 DQ {$$=$2;}
;
att_val1: attchar1 {$$=add_to_string(0,$1);}
| SPACE
| att_val1 attchar1 {$$=add_to_string($1,$2);}
| att_val1 SPACE {$$=add_strings($1,$2);}
;
att_val2: attchar2 {$$=add_to_string(0,$1);}
| SPACE
| att_val2 attchar2 {$$=add_to_string($1,$2);}
| att_val2 SPACE {$$=add_strings($1,$2);}
;
opt_space: 
| SPACE {free_string($1);}
;
end_tag: END name opt_space CLOSE {check_end($2,0);}
;
empty_elem: start1 att_list SLASH CLOSE {check_start($1,$2); check_end($1,1);}
;
cdata: chardata {$$=add_to_string(0,$1);}
| SPACE
| cdata chardata {$$=add_to_string($1,$2);}
| cdata SPACE {$$=add_strings($1,$2);}
;
content: cdata { if(check_ws($1) && call->content) call->content($1); free_string($1); }
| content1 { if(check_ws($1) && call->content) call->content($1); free_string($1); }
| content content1 { if(check_ws($2) && call->content) call->content($2); free_string($2); }
;
content1: element {$$=0;}
| element cdata {$$=$2;}
| comment {$$=0;}
| comment cdata {$$=$2;}
| pi {$$=0;}
| pi cdata {$$=$2;}
;
%%

static int check_ws(string *s)
{
  int i=0;
  char *p;

  if(s) {
    p=get_cstring(s);
    while(*p) {
      if(!isspace((int)*p)) break;
      p++;
    }
    if(*p) i=1;
  }
  return i;
}

static int check_dtd_tok(string *s,char *p) 
{
  int i;

  if(s && !strcmp(get_cstring(s),p)) i=0;
  else {
    i=1;
    if(call->error) call->error(*line_no+1,"Illegal DTD token");
    abt_flag=1;
  }
  return i;
}

static void check_declaration(args *attr)
{
  int st=0,err=0,i;
  char *atts[]={"version","encoding","standalone"};
  args *attr1;
	
  attr1=attr;
  while(attr && !err) {
    for(i=0;i<3;i++) if(!strcmp(attr->name,atts[i])) break;
    if(i==3) {
      if(call->warning) call->warning(*line_no+1,"Illegal XML declaration attribute '%s'\n",attr->name);
      err=1;
      break;
    }
    switch(i) {
    case 0:
      if(st<3) st=3;
      else err=16;
      break;
    case 1:
      if(st<2) st=2;
      else err=16;
      break;
    case 2:
      if(st<1) {
	if(strcmp(attr->att,"yes") && strcmp(attr->att,"no")) {
	  err=17;
	  if(call->error) call->error(*line_no+1,"Illegal XML standalone declaration value '%s'\n",attr->att);
	} else st=1;
      } else err=16;
      break;
    }
    attr=attr->next;
  }
  if(err&16) {
    if(!(err&15) && call->error) call->error(*line_no+1,"Illegal XML declaration attribute order\n");
    abt_flag=1;
  } else if(call->declaration) call->declaration(attr1);
  free_att_list(attr1);
}

static void check_start(string *s,args *attr)
{
  state *st;
	
  if((st=free_state_list)) free_state_list=st->next;
  else st=malloc(sizeof(state));
  st->next=0;
  st->prev=curr_state;
  st->name=s;
  if(curr_state) curr_state->next=st;
  curr_state=st;
  if(call->start_element) call->start_element(s,attr);
  free_att_list(attr);
}

static void check_end(string *s,int fg)
{
  state *st;

  if(!(curr_state)) {
    if(call->error) call->error(*line_no+1,"spurious close of '%s' element\n",get_cstring(s));
    abt_flag=1;
  } else if(strcmp(get_cstring(curr_state->name),get_cstring(s))) {
    if(call->error) call->error(*line_no+1,"mismatched close of '%s' element by '%s'\n",get_cstring(curr_state->name),get_cstring(s));
    abt_flag=1;
  } else {
    st=curr_state->prev;
    if(!fg) free_string(curr_state->name); 
    curr_state->name=0;
    curr_state->next=free_state_list;
    free_state_list=curr_state;
    curr_state=st;
    if(call->end_element) call->end_element(s);
  }
  free_string(s);
}

static args *make_arg(string *s1,string *s2)
{
  args *arg;
	
  arg=malloc(sizeof(args));
  arg->next=0;
  arg->name=extract_cstring(s1);
  arg->att=extract_cstring(s2);
  return arg;
}

static void free_att_list(args *arg)
{
  struct args *arg1;
	
  while(arg) {
    arg1=arg->next;
    free(arg->name);
    free(arg->att);
    free(arg);
    arg=arg1;
  }
}

static int xmlerror(char *s)
{
  if(!(abt_flag)) fprintf(stderr,"line %d, col %d: %s\n",*line_no+1,col_pos,s);
  return 0;
}

static int lex_tab[]={
  CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,SPACE,SPACE,-1,CHAR,CHAR,-2,CHAR,CHAR,
  CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,
  SPACE,CHAR,DQ,CHAR,CHAR,PERCENT,AMPERSAND,SQ,CHAR,CHAR,CHAR,CHAR,CHAR,DASH,DOT,SLASH,
  DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,COLON,SEMICOLON,OPEN,EQ,CLOSE,CHAR,
  CHAR,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,
  LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LSBRACK,CHAR,RSBRACK,CHAR,USCORE,
  CHAR,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,
  LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,CHAR,CHAR,CHAR,CHAR,CHAR
};

static int lex_tab1[]={
  CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,SPACE,SPACE,-1,CHAR,CHAR,-2,CHAR,CHAR,
  CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,CHAR,
  SPACE,CHAR,DQ,CHAR,CHAR,PERCENT,AMPERSAND,SQ,LBRACK,RBRACK,STAR,PLUS,COMMA,DASH,DOT,SLASH,
  DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,DIGIT,COLON,SEMICOLON,OPEN,EQ,CLOSE,QUERY,
  CHAR,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,
  LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LSBRACK,CHAR,RSBRACK,CHAR,USCORE,
  CHAR,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,
  LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,LETTER,CHAR,BAR,CHAR,CHAR,CHAR
};
	  
static int xmllex(yystype *lval)
{
  static int c,fg;
  char *str[]={"OCTYPE","EMENT","TITY","TTLIST","OTATION","CDATA[","MPTY","NY","PCDATA",
	       "EQUIRED","MPLIED","IXED"};
  char *str1[]={"CDATA","IDREFS","IDREF","ID","ENTITY","ENTITIES","NMTOKENS","NMTOKEN",0};
  int atttype[]={CDATA,IDREFS,IDREF,ID,ENTITY,ENTITIES,NMTOKENS,NMTOKEN};
  char *p,buf[16];

  string *s;
  int i=-1,j,c1,err=0,buflen=16;
  
  if(abt_flag) return 0;
  if(!fg) c=fgetc(xmlin);
  else fg=0;
  col_pos++;
  if(c==EOF) return 0;
  if(pi_state) {
    i=0;
    if(pi_state==1 && c=='x') {
      c1=fgetc(xmlin);
      if(c1=='m') {
	c1=fgetc(xmlin);
	if(c1=='l') {
	  i=XMLTOK;
	  col_pos+=2;
	  fg=0;
	} else ungetc(c1,xmlin);
      }
      if(!i) {
	i=lex_tab[c];
	lval->c=(char)c;
	c=c1;
	fg=1;
      }
    } else if(c=='?') {
      c1=fgetc(xmlin);
      if(c1=='>') {
	i=QCLOSE;
	col_pos++;
      } else {
	i=lex_tab[c];
	lval->c=(char)c;
	c=c1;
	fg=1;
      }
    } else {
      i=lex_tab[c];
      lval->c=(char)c;
    }
    pi_state=2;
  } else if(in_comment && c=='-') {
    c1=fgetc(xmlin);
    if(c1=='-') {
      i=DOUBLEDASH;
      col_pos++;
    } else {
      i=lex_tab[c];
      lval->c=(char)c;
      c=c1;
      fg=1;
    }
  } else if(element_state) {
    j=0;
    if(element_state==1) {
      if(c=='E') {
	p=str[6];
	while(*p) {
	  c1=fgetc(xmlin);
	  if(c1!=*p) break;
	  p++;
	}
	if(*p) err=1;
	else i=EMPTY;
	j=1;
      } else if (c=='A') {
	p=str[7];
	while(*p) {
	  c1=fgetc(xmlin);
	  if(c1!=*p) break;
	  p++;
	}
	if(*p) err=1;
	else i=ANY;
	j=1;
      }
    } else if(element_state==2 && c=='#') {
      p=str[8];
      while(*p) {
	c1=fgetc(xmlin);
	if(c1!=*p) break;
	p++;
      }
      if(*p) err=1;
      else i=PCDATA;
      j=1;
    }
    element_state=2;
    if(!j) {
      i=lex_tab1[c];
      lval->c=(char)c;
    }
  } else if(attlist_state==1) {
    i=lex_tab1[c];
    lval->c=(char)c;
    if(i==LETTER) {
      buf[0]=c;
      for(j=1;j<buflen-1;j++) {
	c1=fgetc(xmlin);
	if(c1==EOF || isspace(c1)) {
	  c=c1;
	  fg=1;
	  break;
	}
	buf[j]=c1;
      }
      buf[j]=0;
      i=0;
      p=str1[i];
      while((p=str1[i])) {
	if(!strcmp(p,buf)) break;
	i++;
      }
      if(p) i=atttype[i];
      else err=1;
    }
    attlist_state=2;
  } else if(attlist_state==2) {
    if(c=='#') {
      c1=fgetc(xmlin);
      switch(c1) {
      case 'R':
	p=str[9];
	i=REQUIRED;
	break;
      case 'I':
	p=str[10];
	i=IMPLIED;
	break;
      case 'F':
	p=str[11];
	i=FIXED;
	break;
      default:
	err=1;
      }
      if(!err) {
	while(*p) {
	  c1=fgetc(xmlin);
	  if(c1!=*p) break;
	  p++;
	}
	if(*p) err=1;
      }
    } else {
      i=lex_tab1[c];
      lval->c=(char)c;
    }
  } else if(!in_comment && c=='<') {
    c1=fgetc(xmlin);
    col_pos++;
    err=0;
    if(c1=='?') i=QOPEN;
    else if(c1=='!') {
      col_pos++;
      c1=fgetc(xmlin);
      switch(c1) {
      case '-':
	c1=fgetc(xmlin);
	if(c1=='-') i=COMMENTSTART;
	else err=1;
	break;
      case '[':
	p=str[5];
	while(*p) {
	  c1=fgetc(xmlin);
	  if(c1!=*p) break;
	  p++;
	}
	if(*p) err=1;
	else i=CDATASTART;
	break;
      case 'D':
	p=str[0];
	while(*p) {
	  c1=fgetc(xmlin);
	  if(c1!=*p) break;
	  p++;
	}
	if(*p) err=1;
	else i=DOCTYPE;
	break;
      case 'E':
	c1=fgetc(xmlin);
	if(c1=='L') j=1;
	else if(c1=='N') j=2;
	else err=1;
	if(!err) {
	  p=str[j];
	  while(*p) {
	    c1=fgetc(xmlin);
	    if(c1!=*p) break;
	    p++;
	  }
	  if(*p) err=1;
	  else if(j==1) {
	    i=ELEMENT;
	  } else i=ENTITY;
	}
	break;
      case 'A':
 	p=str[3];
	while(*p) {
	  c1=fgetc(xmlin);
	  if(c1!=*p) break;
	  p++;
	}
	if(*p) err=1;
	else i=ATTLIST;
	break;
      case 'N':
 	p=str[4];
	while(*p) {
	  c1=fgetc(xmlin);
	  if(c1!=*p) break;
	  p++;
	}
	if(*p) err=1;
	else i=NOTATION;
	break;
      default:
	err=1;
	break;
      }
    } else if(c1=='/') i=END;
    else {
      col_pos--;
      i=lex_tab[c];
      lval->c=(char)c;
      c=c1;
      fg=1;
    }
  } else {
    i=lex_tab[c];
    lval->c=(char)c;
  }
  if(err) {
    if(call->error) call->error(*line_no+1,"Illegal construction\n");
    abt_flag=1;
  }
  if(i<0) {
    (*line_no)++;
    col_pos=0;
    if(i==-2) {
      c=fgetc(xmlin);
      if(c!='\n') fg=1;
      else col_pos=1;
      lval->c='\n';
    }
    i=SPACE;
  }
  if(i==SPACE) {
    s=0;
    c1=lval->c;
    do {
      s=add_to_string(s,c1);
      if(!fg) c=fgetc(xmlin);
      else fg=0;
      col_pos++;
      if(c==EOF) break;
      c1=c;
      i=lex_tab[c];
      if(i<0) {
	(*line_no)++;
	col_pos=0;
	if(i==-2) {
	  c=fgetc(xmlin);
	  if(c!='\n') fg=1;
	  else col_pos++;
	  c1='\n';
	}
	i=SPACE;
      }
    } while(i==SPACE);
    fg=1;
    col_pos--;
    lval->str=s;
    return SPACE;
  }
  return i;
}

int Read_XML(FILE *fptr,XML_handler *handler)
{
  int err,line_bk=0;
  state *st;
	
#if YYDEBUG
  xmldebug=1;
#endif
  curr_state=free_state_list=0;
  call=handler;
  xmlin=fptr;
  line_no=handler->line;
  if(!line_no) line_no=&line_bk;
  err=xmlparse();
  if(!err && abt_flag) err=-1;
  if(!err && curr_state) {
    if(call->error) call->error(0,"The following elements were not closed:");
    while(curr_state) {
      st=curr_state->prev;
      if(call->error) call->error(0," %s",get_cstring(curr_state->name));
      free_string(curr_state->name);
      free(curr_state);
      curr_state=st;
    }
    err=-2;
  }
  if(free_state_list) {
    while(free_state_list) {
      st=free_state_list->next;
      free(free_state_list);
      free_state_list=st;
    }
  }
  return err;
}
