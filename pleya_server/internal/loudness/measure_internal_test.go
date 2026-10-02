package loudness

import (
	"math"
	"testing"
)

func TestParseProgressReadsLastOutTimeAndEnd(t *testing.T) {
	stdout := "frame=1\nout_time_us=1000000\nprogress=continue\nframe=2\nout_time_us=2005000\nprogress=end\n"
	ms, sawEnd := parseProgress(stdout)
	if !sawEnd {
		t.Fatal("progress=end niet gezien")
	}
	if ms != 2005 {
		t.Fatalf("gemeten %d ms, verwacht 2005", ms)
	}
}

func TestParseProgressWithoutEndReportsIncomplete(t *testing.T) {
	_, sawEnd := parseProgress("out_time_us=1000000\nprogress=continue\n")
	if sawEnd {
		t.Fatal("progress=end gezien terwijl de stroom nooit eindigde")
	}
}

func TestParseLoudnormExtractsTheInputFields(t *testing.T) {
	stderr := `[Parsed_loudnorm_0 @ 0x1] banner-tekst die ertussen kan staan
{
	"input_i" : "-23.10",
	"input_tp" : "-1.20",
	"input_lra" : "3.40",
	"input_thresh" : "-33.50",
	"output_i" : "-23.00",
	"output_tp" : "-2.00",
	"output_lra" : "3.30",
	"output_thresh" : "-33.30",
	"normalization_type" : "dynamic",
	"target_offset" : "0.00"
}
`
	m, err := parseLoudnorm(stderr)
	if err != nil {
		t.Fatalf("parseLoudnorm: %v", err)
	}
	if m.IntegratedLufs != -23.10 || m.TruePeakDbtp != -1.20 || m.LraLu != 3.40 || m.ThresholdLufs != -33.50 {
		t.Fatalf("parseLoudnorm gaf %+v, verwacht de input_*-velden", m)
	}
}

func TestParseLoudnormHandlesTruePeakSilence(t *testing.T) {
	stderr := `{
	"input_i" : "-70.00",
	"input_tp" : "-inf",
	"input_lra" : "0.00",
	"input_thresh" : "-80.00",
	"output_i" : "-70.00",
	"output_tp" : "-inf",
	"output_lra" : "0.00",
	"output_thresh" : "-80.00",
	"normalization_type" : "dynamic",
	"target_offset" : "0.00"
}`
	m, err := parseLoudnorm(stderr)
	if err != nil {
		t.Fatalf("parseLoudnorm: %v", err)
	}
	if !math.IsInf(m.TruePeakDbtp, -1) {
		t.Fatalf("TruePeakDbtp = %v, verwacht -Inf (stilte heeft geen eindige piek)", m.TruePeakDbtp)
	}
}

func TestParseLoudnormWithoutJSONFails(t *testing.T) {
	if _, err := parseLoudnorm("geen json hier, alleen een foutmelding"); err == nil {
		t.Fatal("verwachtte een fout zonder JSON-blok")
	}
}
