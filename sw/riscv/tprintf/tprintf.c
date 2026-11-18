/* tprintf: a small printf for test programs (see tprintf.h).
 *
 * One formatter writes characters into a sink: a buffer of a given size (tsnprintf), or a
 * small buffer that goes out through semihost_write0 whenever it is full and at the end
 * (tprintf). A conversion is read as %[-][0][width][l]<c>; numbers become digits in a
 * small array, last digit first, then come out padded to the width.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include "tprintf.h"

#include "semihosting.h"

/* Where characters go: buf (size of it, len put so far); flush, when not 0, empties a full
 * buffer and keeps going (tprintf), else characters past the end are counted, not kept. */
typedef struct {
    char*  buf;
    size_t size;
    size_t len;         /* characters in buf now */
    int    total;       /* characters of the whole text */
    int    flush;
} sink_t;

static void sink_flush(sink_t* s)
{
    s->buf[s->len] = '\0';
    semihost_write0(s->buf);
    s->len = 0;
}

static void put(sink_t* s, char c)
{
    s->total++;
    if (s->len + 1 < s->size) {
        s->buf[s->len++] = c;
    } else if (s->flush) {
        sink_flush(s);
        s->buf[s->len++] = c;
    }
}

/* text (n characters) in a field of width: spaces before it, or after it with left. */
static void put_field(sink_t* s, const char* text, int n, int width, int left)
{
    int pad = (width > n) ? width - n : 0;

    if (!left)
        for (int i = 0; i < pad; i++)
            put(s, ' ');
    for (int i = 0; i < n; i++)
        put(s, text[i]);
    if (left)
        for (int i = 0; i < pad; i++)
            put(s, ' ');
}

/* An unsigned number in base 10 or 16 (upper: A-F), with a sign when negative, zeros up to
 * the width with zero. */
static void put_number(sink_t* s, uint32_t v, int negative, unsigned base, int upper,
                       int width, int left, int zero)
{
    const char* digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    char        text[12];
    int         n = 0;

    do {
        text[n++] = digits[v % base];
        v /= base;
    } while (v != 0);
    if (zero && !left) {
        int want = negative ? width - 1 : width;
        while (n < want && n < (int)sizeof text - 1)
            text[n++] = '0';
    }
    if (negative)
        text[n++] = '-';
    for (int i = 0; i < n / 2; i++) {        /* last digit first: reverse */
        char t = text[i];
        text[i] = text[n - 1 - i];
        text[n - 1 - i] = t;
    }
    put_field(s, text, n, width, left);
}

/* A float, its bits, as C99's %a: [-]0x1[.hex]p[+-]exponent, exact; a subnormal normalized
 * (0x1p-149 the smallest), 0x0p+0, inf, nan. */
static void put_hex_float(sink_t* s, uint32_t bits, int width, int left)
{
    char     text[24];
    int      n = 0;
    uint32_t sign = bits >> 31;
    int      e = (int)((bits >> 23) & 0xff);
    uint32_t m = bits & 0x7fffff;            /* the 23 bits after the binary point */
    int      exp;

    if (e == 0xff) {
        const char* word = (m != 0) ? "nan" : (sign ? "-inf" : "inf");
        int         len = 0;
        while (word[len] != '\0')
            len++;
        put_field(s, word, len, width, left);
        return;
    }
    if (sign)
        text[n++] = '-';
    text[n++] = '0';
    text[n++] = 'x';
    if (e == 0 && m == 0) {
        text[n++] = '0';
        exp = 0;
    } else {
        if (e == 0) {                        /* subnormal: normalize */
            exp = -126;
            while ((m & 0x800000) == 0) {
                m <<= 1;
                exp--;
            }
            m &= 0x7fffff;
        } else {
            exp = e - 127;
        }
        text[n++] = '1';
        m <<= 1;                             /* 24 bits: six hex digits */
        if (m != 0) {
            text[n++] = '.';
            for (int d = 20; d >= 0 && m != 0; d -= 4) {
                text[n++] = "0123456789abcdef"[(m >> d) & 0xf];
                m &= (1u << d) - 1;
            }
        }
    }
    text[n++] = 'p';
    text[n++] = (exp < 0) ? '-' : '+';
    {
        uint32_t a = (uint32_t)((exp < 0) ? -exp : exp);
        char     d[4];
        int      k = 0;
        do {
            d[k++] = (char)('0' + a % 10);
            a /= 10;
        } while (a != 0);
        while (k > 0)
            text[n++] = d[--k];
    }
    put_field(s, text, n, width, left);
}

static void format(sink_t* s, const char* fmt, va_list ap)
{
    for (; *fmt != '\0'; fmt++) {
        const char* start = fmt;
        int         left = 0;
        int         zero = 0;
        int         width = 0;

        if (*fmt != '%') {
            put(s, *fmt);
            continue;
        }
        fmt++;
        for (; *fmt == '-' || *fmt == '0'; fmt++) {
            if (*fmt == '-')
                left = 1;
            else
                zero = 1;
        }
        for (; *fmt >= '0' && *fmt <= '9'; fmt++)
            width = width * 10 + (*fmt - '0');
        if (*fmt == 'l')
            fmt++;
        switch (*fmt) {
        case 'd':
        case 'i': {
            int v = va_arg(ap, int);
            put_number(s, (v < 0) ? 0u - (uint32_t)v : (uint32_t)v, v < 0, 10, 0, width,
                       left, zero);
            break;
        }
        case 'u':
            put_number(s, va_arg(ap, unsigned), 0, 10, 0, width, left, zero);
            break;
        case 'x':
        case 'X':
            put_number(s, va_arg(ap, unsigned), 0, 16, *fmt == 'X', width, left, zero);
            break;
        case 'p':
            put(s, '0');
            put(s, 'x');
            put_number(s, (uint32_t)(uintptr_t)va_arg(ap, void*), 0, 16, 0, 8, 0, 1);
            break;
        case 'c': {
            char c = (char)va_arg(ap, int);
            put_field(s, &c, 1, width, left);
            break;
        }
        case 's': {
            const char* str = va_arg(ap, const char*);
            int         len = 0;
            if (str == 0)
                str = "(null)";
            while (str[len] != '\0')
                len++;
            put_field(s, str, len, width, left);
            break;
        }
        case 'a':
            put_hex_float(s, va_arg(ap, uint32_t), width, left);
            break;
        case '%':
            put(s, '%');
            break;
        default:                             /* unknown, or the format ends: as written */
            for (; start <= fmt && *start != '\0'; start++)
                put(s, *start);
            if (*fmt == '\0')
                return;
            break;
        }
    }
}

int tvsnprintf(char* buf, size_t size, const char* fmt, va_list ap)
{
    sink_t s = {buf, size, 0, 0, 0};

    format(&s, fmt, ap);
    if (size > 0)
        buf[s.len] = '\0';
    return s.total;
}

int tsnprintf(char* buf, size_t size, const char* fmt, ...)
{
    va_list ap;
    int     n;

    va_start(ap, fmt);
    n = tvsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return n;
}

int tprintf(const char* fmt, ...)
{
    char    buf[80];
    sink_t  s = {buf, sizeof buf, 0, 0, 1};
    va_list ap;

    va_start(ap, fmt);
    format(&s, fmt, ap);
    va_end(ap);
    if (s.len > 0)
        sink_flush(&s);
    return s.total;
}
