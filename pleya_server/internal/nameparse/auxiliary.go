package nameparse

import (
	"path"
	"strings"
)

// ClassifyAuxiliaryVideo returns a scanner-only classification, not an identity
// or permission. Only exact auxiliary directories below a show are evidence;
// bare titles such as Sample or Trailer are deliberately left ambiguous.
func ClassifyAuxiliaryVideo(libraryKind, relPath string) string {
	if libraryKind != "shows" || path.IsAbs(relPath) || path.Clean(relPath) != relPath ||
		strings.HasPrefix(relPath, "../") || strings.Contains(relPath, `\`) || Classify(relPath) != KindVideo {
		return ""
	}
	dir, file := path.Split(relPath)
	segments := splitSegments(dir)
	// Segment zero names the show, even when the show itself is named Extras.
	if len(segments) < 2 || seasonDirRe.MatchString(segments[0]) {
		return ""
	}
	stack, _ := splitPart(strings.TrimSuffix(file, path.Ext(file)))
	if _, _, _, ok := episodeNumbers(stack); ok {
		return ""
	}
	if _, _, _, ok := markerNumber(stack); ok {
		return ""
	}
	// Real specials remain episodes, including auxiliary-looking subdirectories
	// of a specials season. A folder name is never stronger than that boundary.
	for _, segment := range segments[1:] {
		if strings.EqualFold(segment, "specials") {
			return ""
		}
		if m := seasonDirRe.FindStringSubmatch(segment); m != nil && strings.TrimLeft(m[1], "0") == "" {
			return ""
		}
	}
	for _, segment := range segments[1:] {
		switch strings.ToLower(segment) {
		case "samples":
			return "sample"
		case "trailers":
			return "trailer"
		case "extras":
			return "extras"
		}
	}
	return ""
}
