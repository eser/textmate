#include "render.h"
#include <oak/oak.h>
#include <cf/cf.h>

namespace render
{
	void fill_rect (ng::context_t const& context, CGColorRef color, CGRect const& rect)
	{
		ASSERT(color);
		context.fill_rect(color, rect);
	}

} /* render */
