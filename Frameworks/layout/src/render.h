#ifndef RENDER_H_V8XB081V
#define RENDER_H_V8XB081V

#include <oak/debug.h>
#include <theme/theme.h>
#include "ct.h"

namespace render
{
	// Routes through context_t for Metal/CoreText dual-mode support
	void fill_rect (ng::context_t const& context, CGColorRef color, CGRect const& rect);

} /* render */

#endif /* end of include guard: RENDER_H_V8XB081V */
