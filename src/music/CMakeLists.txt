# Música vía BASS: librería propietaria Windows-only (lib/bass.dll); solo en Windows.
IF (CMAKE_HOST_WIN32)
	ADD_SUBDIRECTORY (BASS)
ENDIF (CMAKE_HOST_WIN32)

