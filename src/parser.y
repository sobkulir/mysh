%error-verbose
%define	parse.lac full

%{
#include <assert.h>
#include <err.h>
#include <stdio.h>
#include <sys/queue.h>

#include "execute.h"
#include "cmd.h"
#include "parser.h"
#include "utils.h"

/* Functions defined in flex. */
extern int yylex();
extern int yylex_destroy();
extern void init_lexer_with_line(char *);
extern void yyerror(const char *);

/* Line number of currectly parsed line. */
static int line_num = 0;
/* seq_list containing the parsed line. */
static seq_list_t *rootp = NULL;
%}

%union {
	char *word_un;
	arg_list_t *arg_list_un;
	redir_list_t *redir_list_un;
	command_t *command_un;
	piped_list_t *piped_list_un;
	seq_list_t *seq_list_un;
}

%destructor { free($$); } <word_un>
%destructor { free_arg_list($$); } <arg_list_un>
%destructor { free_redir_list($$); } <redir_list_un>
%destructor { free_command($$); } <command_un>
%destructor { free_piped_list($$); } <piped_list_un>
%destructor { free_seq_list($$); } <seq_list_un>

%token END_OF_FILE END_OF_LINE
%token REDIRECT_IN REDIRECT_OUT REDIRECT_APPEND_OUT
%token <word_un> WORD

%left SEQUENTIAL
%left PIPE

%type <seq_list_un> seq_list
%type <seq_list_un> root_internal
%type <piped_list_un> piped_list
%type <command_un> command
%type <redir_list_un> redir
%type <redir_list_un> redir_list
%type <arg_list_un> arg_list

%start root

%%

root:
	root_internal {
		rootp = $1;
		YYACCEPT;
	}

root_internal:
	seq_list END_OF_LINE { $$ = $1; }
	| seq_list END_OF_FILE { $$ = $1; }
	| seq_list SEQUENTIAL END_OF_LINE { $$ = $1; }
	| seq_list SEQUENTIAL END_OF_FILE { $$ = $1; }
	| END_OF_LINE { $$ = NULL; }
	| END_OF_FILE { $$ = NULL; }

seq_list:
	piped_list {
		seq_list_t *sl =
			(seq_list_t *) safe_malloc(sizeof (seq_list_t));
		STAILQ_INIT(sl);
		append_seq_list(sl, $1);
		$$ = sl;
	}
	| seq_list SEQUENTIAL piped_list {
		append_seq_list($1, $3);
		$$ = $1;
	}

piped_list:
	command {
		piped_list_t * pl =
			(piped_list_t *)
			safe_malloc(sizeof (piped_list_t));
		STAILQ_INIT(pl);
		append_piped_list(pl, $1);
		$$ = pl;
	}
	| piped_list PIPE command {
		append_piped_list($1, $3);
		$$ = $1;
	}

command:
	redir_list arg_list redir_list {
		command_t *cmdp =
			(command_t *) safe_malloc(sizeof (command_t));
		cmdp->arg_list = $2;
		STAILQ_CONCAT($1, $3);
		free($3);
		cmdp->redir_list = $1;
		$$ = cmdp;
	}

redir_list:
	/* empty */ { $$ = create_redir_list(); }
	| redir_list redir {
		STAILQ_CONCAT($1, $2);
		free($2);
		$$ = $1;
	}

redir:
	REDIRECT_IN WORD {
		$$ = create_redir_list();
		append_redir_list($$, REDIR_IN, $2);
	}
	| REDIRECT_OUT WORD {
		$$ = create_redir_list();
		append_redir_list($$, REDIR_OUT, $2);
	}
	| REDIRECT_APPEND_OUT WORD {
		$$ = create_redir_list();
		append_redir_list($$, REDIR_APPEND_OUT, $2);
	}

arg_list:
	arg_list WORD {
		append_arg_list($1, $2);
		$$ = $1;
	}
	| WORD {
		arg_list_t * wl =
			(arg_list_t *) safe_malloc(sizeof (arg_list_t));
		STAILQ_INIT(wl);
		append_arg_list(wl, $1);
		$$ = wl;
	}
%%

int
parse_line(char * line, int curline, seq_list_t **rootpp) {
	assert(line != NULL);

	init_lexer_with_line(line);
	line_num = curline;

	if (yyparse() != 0)
		return (1);

	yylex_destroy();

	*rootpp = rootp;
	return (0);
}

void
yyerror(const char *msg)
{
	fprintf(stderr, "error:%d: %s\n", line_num, msg);
}
