package catalog

import (
	"math/rand"
	"sort"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

func orderedRows(n int) ([]listRow, []id.ID) {
	rows := make([]listRow, n)
	items := make([]id.ID, n)
	for i := range rows {
		items[i] = id.New()
		rows[i] = listRow{Item: items[i], Position: int64(i+1) * listPositionGap}
	}
	return rows, items
}

// applied zet de writes op de rijen en geeft de items op volgorde.
func applied(rows []listRow, writes []listRow, target []id.ID) []id.ID {
	byItem := map[id.ID]int64{}
	for _, row := range rows {
		byItem[row.Item] = row.Position
	}
	for _, write := range writes {
		byItem[write.Item] = write.Position
	}
	keep := map[id.ID]bool{}
	for _, item := range target {
		keep[item] = true
	}
	out := []listRow{}
	for item, position := range byItem {
		if keep[item] {
			out = append(out, listRow{Item: item, Position: position})
		}
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Position < out[b].Position })
	items := make([]id.ID, len(out))
	for i, row := range out {
		items[i] = row.Item
	}
	return items
}

func sameOrder(a, b []id.ID) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// TestMovingOneItemWritesOneRow is acceptatiecriterium 2 van PS-9C: één item van
// plek 1 naar plek 400 laat de andere 399 rijen ongemoeid.
func TestMovingOneItemWritesOneRow(t *testing.T) {
	rows, items := orderedRows(400)
	target := append(append([]id.ID{}, items[1:]...), items[0])

	writes := planListOrder(rows, target)
	if len(writes) != 1 || writes[0].Item != items[0] {
		t.Fatalf("%d rijen geschreven, verwacht alleen het verplaatste item", len(writes))
	}
	if !sameOrder(applied(rows, writes, target), target) {
		t.Fatal("de volgorde klopt niet na de verplaatsing")
	}

	// Terug naar het begin: ook één rij, nu met een sleutel vóór de rest.
	moved := append([]listRow{}, rows...)
	moved[0].Position = writes[0].Position
	back := planListOrder(moved, items)
	if len(back) != 1 || !sameOrder(applied(moved, back, items), items) {
		t.Fatalf("terugzetten schreef %d rijen", len(back))
	}
}

// TestMovingIntoTheSameGapRenumbersWhenItRunsOut drukt steeds een item tussen
// dezelfde twee buren, tot de ruimte op is. Dan hernummert de lijst, en de
// volgorde blijft kloppen.
func TestMovingIntoTheSameGapRenumbersWhenItRunsOut(t *testing.T) {
	rows, items := orderedRows(40)
	renumbered := false
	order := append([]id.ID{}, items...)
	for i := 2; i < 40; i++ {
		// Elk volgend item naar de tweede plek.
		item := order[i]
		copy(order[2:i+1], order[1:i])
		order[1] = item
		writes := planListOrder(rows, order)
		renumbered = renumbered || len(writes) > 2
		byItem := map[id.ID]int64{}
		for _, row := range rows {
			byItem[row.Item] = row.Position
		}
		for _, write := range writes {
			byItem[write.Item] = write.Position
		}
		for j := range rows {
			rows[j].Position = byItem[rows[j].Item]
		}
		if !sameOrder(applied(rows, nil, order), order) {
			t.Fatalf("volgorde klopt niet na zet %d", i)
		}
	}
	if !renumbered {
		t.Fatal("de hernummering is nooit nodig geweest; de test bewijst niets")
	}
}

// TestPlanHandlesAnyPermutationAndNewItems is de brede controle: wat er ook
// binnenkomt, de sleutels leveren de gevraagde volgorde op.
func TestPlanHandlesAnyPermutationAndNewItems(t *testing.T) {
	random := rand.New(rand.NewSource(19))
	for round := range 200 {
		rows, items := orderedRows(random.Intn(30))
		target := append([]id.ID{}, items...)
		random.Shuffle(len(target), func(a, b int) { target[a], target[b] = target[b], target[a] })
		if len(target) > 0 {
			target = target[:random.Intn(len(target)+1)]
		}
		for range random.Intn(4) {
			at := random.Intn(len(target) + 1)
			target = append(target[:at], append([]id.ID{id.New()}, target[at:]...)...)
		}
		writes := planListOrder(rows, target)
		if !sameOrder(applied(rows, writes, target), target) {
			t.Fatalf("ronde %d: de volgorde klopt niet", round)
		}
	}
}
