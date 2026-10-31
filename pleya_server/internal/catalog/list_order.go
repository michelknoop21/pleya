package catalog

import (
	"sort"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// listPositionGap is de afstand tussen twee nieuwe rijen. Tussen twee buren passen
// zo twintig keer een halvering voordat de lijst moet worden hernummerd.
const listPositionGap int64 = 1 << 20

// listRow is één rij: een item en zijn sleutel in de lijst.
type listRow struct {
	Item     id.ID
	Position int64
}

// planListOrder bepaalt welke rijen een nieuwe sleutel nodig hebben om target te
// realiseren, en doet dat met zo weinig mogelijk rijen (acceptatiecriterium 2 van
// PS-9C): de langste reeks die al in de goede volgorde staat blijft staan, en
// alleen wat eromheen ligt krijgt een sleutel tussen zijn buren.
//
// Een item uit target dat nog niet bestaat krijgt zo ook zijn sleutel. Past een
// reeks niet meer tussen zijn buren, dan wordt de hele lijst hernummerd; dat is
// de enige weg die elke rij schrijft, en hij komt pas na veel verplaatsingen op
// dezelfde plek.
func planListOrder(existing []listRow, target []id.ID) []listRow {
	current := make(map[id.ID]int64, len(existing))
	for _, row := range existing {
		current[row.Item] = row.Position
	}

	kept := keptInOrder(current, target)
	positions := make([]int64, len(target))
	fits := true
	for start := 0; start < len(target) && fits; {
		if kept[start] {
			positions[start] = current[target[start]]
			start++
			continue
		}
		end := start
		for end < len(target) && !kept[end] {
			end++
		}
		fits = fillRun(positions, start, end, current, target, kept)
		start = end
	}
	if !fits {
		for i := range target {
			positions[i] = int64(i+1) * listPositionGap
		}
	}

	writes := make([]listRow, 0, len(target))
	for i, item := range target {
		if old, ok := current[item]; !ok || old != positions[i] {
			writes = append(writes, listRow{Item: item, Position: positions[i]})
		}
	}
	return writes
}

// fillRun geeft de rijen start tot end gelijkmatig verdeelde sleutels tussen de
// rij ervoor en de rij erna. Zonder buur aan een kant is de ruimte daar onbeperkt.
func fillRun(positions []int64, start, end int, current map[id.ID]int64, target []id.ID, kept []bool) bool {
	count := int64(end - start)
	hasAfter := end < len(target) && kept[end]
	switch {
	case start == 0 && !hasAfter:
		for i := start; i < end; i++ {
			positions[i] = int64(i+1) * listPositionGap
		}
	case start == 0:
		first := current[target[end]] - count*listPositionGap
		for i := start; i < end; i++ {
			positions[i] = first + int64(i-start)*listPositionGap
		}
	case !hasAfter:
		for i := start; i < end; i++ {
			positions[i] = positions[start-1] + int64(i-start+1)*listPositionGap
		}
	default:
		low, high := positions[start-1], current[target[end]]
		step := (high - low) / (count + 1)
		if step < 1 {
			return false
		}
		for i := start; i < end; i++ {
			positions[i] = low + int64(i-start+1)*step
		}
	}
	return true
}

// keptInOrder markeert per index van target of die rij kan blijven staan: de
// langste stijgende deelreeks van de bestaande sleutels, in target-volgorde.
func keptInOrder(current map[id.ID]int64, target []id.ID) []bool {
	kept := make([]bool, len(target))
	// tails[n] is de index in target van de kleinste eindsleutel van een reeks
	// met lengte n+1, previous de voorganger per index.
	tails := make([]int, 0, len(target))
	previous := make([]int, len(target))
	for i, item := range target {
		position, ok := current[item]
		if !ok {
			continue
		}
		place := sort.Search(len(tails), func(n int) bool { return current[target[tails[n]]] >= position })
		previous[i] = -1
		if place > 0 {
			previous[i] = tails[place-1]
		}
		if place == len(tails) {
			tails = append(tails, i)
		} else {
			tails[place] = i
		}
	}
	if len(tails) > 0 {
		for i := tails[len(tails)-1]; i >= 0; i = previous[i] {
			kept[i] = true
		}
	}
	return kept
}
