package career

import "testing"

func profile() FitProfile {
	coding := 80.0
	return FitProfile{
		Traits: map[string]float64{"investigative": 90, "realistic": 60, "conventional": 30, "conscientiousness": 80, "openness": 60},
		Coding: &coding,
	}
}

func TestInterestFitWeightsFirstLetterMost(t *testing.T) {
	got := InterestFit(profile(), "IRC") // (3*90 + 2*60 + 1*30) / 6 = 70
	if got == nil || *got != 70 {
		t.Fatalf("want 70, got %v", got)
	}
	other := InterestFit(profile(), "CRI") // (3*30 + 2*60 + 90) / 6 = 50
	if other == nil || *other != 50 {
		t.Fatalf("want 50, got %v", other)
	}
}

func TestFitIsNilWithoutData(t *testing.T) {
	empty := FitProfile{Traits: map[string]float64{}}
	if InterestFit(empty, "IRC") != nil || PersonalityFit(empty, []string{"openness"}) != nil || CodingFit(empty, 1) != nil {
		t.Error("no data should give no fit, not a zero")
	}
	if InterestFit(profile(), "") != nil {
		t.Error("a career without a code has no interest fit")
	}
	if Combine(nil, nil, nil, 1) != nil {
		t.Error("nothing to combine")
	}
}

func TestPersonalityAndCodingFit(t *testing.T) {
	if v := PersonalityFit(profile(), []string{"conscientiousness", "openness", "unknown"}); v == nil || *v != 70 {
		t.Errorf("personality: %v", v)
	}
	if CodingFit(profile(), 0) != nil {
		t.Error("coding must not count for a career that does not use it")
	}
	if v := CodingFit(profile(), 0.5); v == nil || *v != 80 {
		t.Errorf("coding: %v", v)
	}
}

func TestCombineReweightsMissingParts(t *testing.T) {
	a, b := 80.0, 40.0
	if v := Combine(&a, nil, nil, 0); v == nil || *v != 80 {
		t.Errorf("only interest: %v", v)
	}
	// interest 0.4 and personality 0.3: (80*0.4 + 40*0.3) / 0.7 = 62.86
	if v := Combine(&a, &b, nil, 0); v == nil || *v != 62.86 {
		t.Errorf("two parts: %v", v)
	}
}

func TestBlendOnlyNudgesTheScore(t *testing.T) {
	if Blend(60, nil) != 60 {
		t.Error("without fit data the score is unchanged")
	}
	full := 100.0
	if got := Blend(60, &full); got != 70 { // 60*0.75 + 100*0.25
		t.Errorf("got %v", got)
	}
	zero := 0.0
	if got := Blend(60, &zero); got != 45 {
		t.Errorf("got %v", got)
	}
}

func TestEvaluateNotes(t *testing.T) {
	d := Evaluate(profile(), "IRC", []string{"conscientiousness", "openness"}, 1)
	if d.Score == nil || len(d.Notes) == 0 {
		t.Fatalf("expected a score and notes, got %+v", d)
	}
	none := Evaluate(FitProfile{Traits: map[string]float64{}}, "IRC", nil, 1)
	if none.Score != nil || len(none.Notes) != 0 {
		t.Errorf("no data should give nothing: %+v", none)
	}
}
