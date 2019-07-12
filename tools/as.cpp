/**@file
 * @brief  Assembler
 * @author Igor Lesik 2019
 */
#include <cstdlib>
#include <cassert>
#include <argp.h>

const char* argp_program_version = "as 1.0";
const char* argp_program_bug_address = "<igor@???.org>";

static struct argp_option arg_options[] = {
    {"verbose",  'v', 0,      0,  "Produce verbose output" },
    {"output",   'o', "FILE", 0,  "Output to FILE instead of standard output" },
    {"input",    'i', "FILE", 0,  "Input from FILE instead of standard input" },
    { 0 }
};

struct Options
{
    char* arg = nullptr;
    bool  verbose = false;
    char* output_file_name = nullptr;
    char* input_file_name  = nullptr;

    FILE* input_file = stdin;
    FILE* output_file = stdout;
};

static
error_t parse_opt(int key, char* arg, struct argp_state* state)
{
    Options* options = (Options*)state->input;

    switch (key)
    {
    case 'v':
        options->verbose = true;
        break;
    case 'o':
        options->output_file_name = arg;
        break;
    case 'i':
        options->input_file_name = arg;
        break;

    case ARGP_KEY_ARG:
        if (state->arg_num >= 1) { // Too many arguments.
            argp_usage (state);
        }
        options->arg/*[state->arg_num]*/ = arg;
        break;
    case ARGP_KEY_END:
        break;

    default:
        return ARGP_ERR_UNKNOWN;
    }

    return 0;
}

/* Program documentation. */
static char doc[] =
    "documention\n"
    "is not\n"
    "written yet";

static struct argp argp = { arg_options, parse_opt, 0, doc };

class AsmParser
{
public:
    void parse(Options& options);
};

void AsmParser::parse(Options& options)
{
    assert(options.input_file);
    FILE* f = options.input_file;

    char c;
    bool new_line = true;
    //bool new_token = true;

    auto skip_to_eol = [&]() -> void {
        while ((c=fgetc(f)) != '\n' and c != EOF);
        new_line = true;
    };

    auto parse_directive = [&]() -> void {
        skip_to_eol();
    };

    auto parse_code = [&]() -> void {
        char s[128] = { c, '\0'};
        unsigned int pos = 1;
        while ((c=fgetc(f)) != EOF and isalnum(c)) { s[pos++] = c; }
        s[pos] = '\0';
        printf("instruction: %s\n", s);
    };

    while ((c=fgetc(f)) != EOF)
    {
        switch (c)
        {
        case ';': // single line comment
            skip_to_eol();
            break;
        case '\n':
            /*new_token =*/ new_line = true;
            break;
        case ' ': case '\t':
            //new_token = true;
            break;
        case '.':
            parse_directive();
            break;
        default:
            if (isalpha(c)) { parse_code(); }
            break;
        }
    }
}

int main(int argc, char* argv[])
{
    Options options;

    argp_parse(&argp, argc, argv, 0, 0, &options);

    if (options.input_file_name) {
        options.input_file = fopen(options.input_file_name, "r");
        if (options.input_file == nullptr) {
            fprintf(stderr, "can't open input file %s\n", options.input_file_name);
            return EXIT_FAILURE;
        }
    }

    if (options.output_file_name) {
        options.output_file = fopen(options.output_file_name, "w");
        if (options.output_file == nullptr) {
            fprintf(stderr, "can't open output file %s\n", options.output_file_name);
            if (options.input_file_name) { fclose(options.input_file); }
            return EXIT_FAILURE;
        }
    }

    AsmParser parser;

    parser.parse(options);

    if (options.input_file_name) { fclose(options.input_file); }

    if (options.output_file_name) { fclose(options.output_file); }

    return EXIT_SUCCESS;
}
