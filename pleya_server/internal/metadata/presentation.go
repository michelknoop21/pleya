package metadata

import (
	"context"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// preparePresentation uses the existing bounded download/cache pipeline and
// generation-guarded CommitMetadata. No image reference is published before it
// belongs to a committed, same-item artwork row.
func (r *Runner) preparePresentation(ctx context.Context, target catalog.MetadataTarget, details *catalog.MetadataDetails, prepared *[]preparedArtwork, retry **time.Time) {
	p := details.Presentation
	resolved := map[string]*id.ID{}
	fetch := func(kind, ref string) *id.ID {
		if ref == "" {
			return nil
		}
		if value, ok := resolved[kind]; ok {
			return value
		}
		resolved[kind] = nil
		saved, err := r.prepareImage(ctx, target.ID, kind, ref)
		if err != nil {
			next := time.Now().Add(r.retryArtwork)
			*retry = &next
			return nil
		}
		if saved != nil {
			*prepared = append(*prepared, *saved)
			value := saved.row.ID
			resolved[kind] = &value
			return &value
		}
		existing, found, err := r.store.GetProviderArtwork(ctx, target.ID, kind, r.name)
		if err != nil || !found || existing.SourceRef != ref {
			next := time.Now().Add(r.retryArtwork)
			*retry = &next
			return nil
		}
		value := existing.ID
		resolved[kind] = &value
		return &value
	}
	p.LogoID = fetch(catalog.LogoKind(p.LogoRef), p.LogoRef)
	// Bound network work regardless of provider credit count.
	if len(p.Portraits) > 18 {
		p.Portraits = p.Portraits[:18]
	}
	for i := range p.Portraits {
		portrait := &p.Portraits[i]
		portrait.ID = fetch(catalog.PortraitKind(portrait.Ref), portrait.Ref)
	}
}
