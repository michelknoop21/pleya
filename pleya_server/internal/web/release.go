//go:build release

package web

import _ "embed"

// Een releasebuild eist een echte frontend.
//
// Deze embed-regel wijst naar één concreet bestand in plaats van naar een map.
// Ontbreekt het, dan faalt `go build -tags release` op de compiler met
// "pattern dist/index.html: no matching files found", en dat is precies de
// bedoeling: liever luid falen dan stil een lege pagina meeleveren. Dezelfde
// redenering als achter de harde ffmpeg-pin in de Dockerfile (DEC-044).
//
// De ontwikkel- en testbuild draagt deze regel niet en compileert dus zonder
// bundel, zodat `go test ./...` geen Bun nodig heeft.
//
//go:embed dist/index.html
var releaseIndex []byte

func init() {
	if len(releaseIndex) == 0 {
		panic("pleya_web: dist/index.html is leeg in een releasebuild")
	}
}
