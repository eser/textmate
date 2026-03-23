#ifndef PARSER_FWD_H_T20BLRIP
#define PARSER_FWD_H_T20BLRIP

#include <memory>
#include <variant>

namespace parser
{
	// Box type replaces boost::recursive_wrapper — stores T on the heap
	// but provides value-like access. std::visit sees T (not box<T>)
	// because we specialize the visitor dispatch below.
	template <typename T>
	struct box
	{
		std::unique_ptr<T> _ptr;

		box () : _ptr(std::make_unique<T>()) { }
		box (T const& v) : _ptr(std::make_unique<T>(v)) { }
		box (T&& v) : _ptr(std::make_unique<T>(std::move(v))) { }
		box (box const& rhs) : _ptr(std::make_unique<T>(*rhs._ptr)) { }
		box (box&& rhs) = default;
		box& operator= (box const& rhs) { if(this != &rhs) _ptr = std::make_unique<T>(*rhs._ptr); return *this; }
		box& operator= (box&& rhs) = default;

		T& operator* () { return *_ptr; }
		T const& operator* () const { return *_ptr; }
		T* operator-> () { return _ptr.get(); }
		T const* operator-> () const { return _ptr.get(); }

		operator T& () { return *_ptr; }
		operator T const& () const { return *_ptr; }
	};

	struct text_t;
	struct placeholder_t;
	struct placeholder_transform_t;
	struct placeholder_choice_t;
	struct variable_t;
	struct variable_transform_t;
	struct variable_fallback_t;
	struct variable_condition_t;
	struct variable_change_t;
	struct case_change_t;
	struct code_t;

	typedef std::variant<
		box<text_t>,
		box<placeholder_t>, box<placeholder_transform_t>, box<placeholder_choice_t>,
		box<variable_t>, box<variable_transform_t>, box<variable_fallback_t>, box<variable_condition_t>, box<variable_change_t>,
		box<case_change_t>,
		box<code_t>
	> node_t;

	typedef std::vector<node_t> nodes_t;

	// Visit helper that unwraps box<T> → T& before calling the visitor
	template <typename Visitor, typename Variant>
	auto visit_node (Visitor&& vis, Variant&& var)
	{
		return std::visit([&vis](auto&& boxed) -> decltype(auto) {
			return vis(*boxed);
		}, std::forward<Variant>(var));
	}

} /* parser */

#endif /* end of include guard: PARSER_FWD_H_T20BLRIP */
