# BASS es audio propietario Windows-only (lib/bass.dll); solo en Windows.
IF (CMAKE_HOST_WIN32)
	ADD_SUBDIRECTORY (BASS-stream)
ENDIF (CMAKE_HOST_WIN32)
ADD_SUBDIRECTORY (NoSoundCard)

