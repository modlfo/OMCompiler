#if !defined(DCS_INTERFACE)
#define DCS_INTERFACE

#if (defined _MSC_VER) && _MSC_VER<1300
#pragma warning (disable : 4786)
#endif

#if defined( _WIN32 ) && defined( _MSC_VER )
#  if defined DCS_EXPORTS
#    define EXPORT __declspec( dllexport )
#  else
#    define EXPORT __declspec( dllimport )
#    pragma warning( disable : 4251 )  // 'identifier' : class 'type' needs to have dll-interface to be used by clients of class 'type2'
#  endif
#endif

#if !defined(EXPORT)
#define EXPORT
#endif

#endif

#pragma warning(  disable : 4297 )        // Issue warning 4297
