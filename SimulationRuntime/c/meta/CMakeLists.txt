# Sources and Headers
SET(META_SRC 	meta_modelica_builtin.c
				meta_modelica_string_lit.c
				realString.c
				meta_modelica_catch.c
				meta_modelica.c
				meta_modelica_segv.c
				gc/mmc_gc.c)

SET(META_HFILES meta_modelica_builtin.h
				meta_modelica_builtin_boxptr.h
				meta_modelica_segv.h
				meta_modelica_string_lit.h
				meta_modelica.h
				gc/mmc_gc.h)


# Library meta
add_library(meta  ${META_SRC} ${META_HFILES})
#set_property(TARGET f2c PROPERTY PREFIX lib)

# Install
INSTALL(TARGETS meta
		ARCHIVE DESTINATION lib/omc)
#INSTALL(FILES ${META_HFILES} DESTINATION include/meta)

