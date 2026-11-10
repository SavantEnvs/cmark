#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "cmark.h"

/* Streams markdown into cmark_parser_feed in caller-chosen chunks, zero-length ones included, each
   chunk in its own exactly-sized heap block so that any read past a chunk's end is an ASan error. */
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  int options;
  if (size < sizeof(options))
    return 0;
  memcpy(&options, data, sizeof(options));
  data += sizeof(options);
  size -= sizeof(options);
  options &= (CMARK_OPT_SOURCEPOS | CMARK_OPT_HARDBREAKS | CMARK_OPT_UNSAFE | CMARK_OPT_NOBREAKS |
              CMARK_OPT_NORMALIZE | CMARK_OPT_VALIDATE_UTF8 | CMARK_OPT_SMART);

  cmark_parser *parser = cmark_parser_new(options);
  while (size > 0) {
    /* one length byte, then that many bytes of chunk (0..23, fewer at the end of the input) */
    size_t len = data[0] % 24;
    data++;
    size--;
    if (len > size)
      len = size;
    char *chunk = (char *)malloc(len);
    if (len > 0)
      memcpy(chunk, data, len);
    cmark_parser_feed(parser, chunk, len);
    free(chunk);
    data += len;
    size -= len;
  }
  cmark_node *doc = cmark_parser_finish(parser);
  cmark_parser_free(parser);

  free(cmark_render_commonmark(doc, options, 0));
  free(cmark_render_html(doc, options));
  cmark_node_free(doc);
  return 0;
}
