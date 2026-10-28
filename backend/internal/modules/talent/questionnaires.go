// Package talent holds what the college knows about a student beyond marks: three short questionnaires
// (personality, interests and values, learning behaviour), coding-platform profiles and projects. Scores
// are worked out in code from the answers, so every number can be traced back to them.
package talent

// Question is one item of a questionnaire. Reverse items are worded the opposite way round and are scored
// as 6 minus the answer, so that a high score always means "more of the trait".
type Question struct {
	ID      string `json:"id"`
	Text    string `json:"text"`
	Trait   string `json:"trait"`
	Reverse bool   `json:"-"`
}

// Trait is something a questionnaire measures.
type Trait struct {
	Key   string `json:"key"`
	Label string `json:"label"`
}

type Questionnaire struct {
	Kind      string     `json:"kind"`
	Title     string     `json:"title"`
	Intro     string     `json:"intro"`
	Scale     []string   `json:"scale"` // labels for answers 1 to 5
	Traits    []Trait    `json:"traits"`
	Questions []Question `json:"questions"`
}

var agreeScale = []string{"Strongly disagree", "Disagree", "Neutral", "Agree", "Strongly agree"}

var personality = Questionnaire{
	Kind:  "personality",
	Title: "Personality",
	Intro: "There are no right or wrong answers. Choose how well each statement describes you in everyday life.",
	Scale: agreeScale,
	Traits: []Trait{
		{"extraversion", "Extraversion"},
		{"agreeableness", "Agreeableness"},
		{"conscientiousness", "Conscientiousness"},
		{"stability", "Emotional stability"},
		{"openness", "Openness"},
	},
	Questions: []Question{
		{"e1", "I enjoy starting conversations with people I have just met.", "extraversion", false},
		{"e2", "I feel energised when I am around other people.", "extraversion", false},
		{"e3", "I prefer to stay in the background in group activities.", "extraversion", true},
		{"e4", "I find it tiring to spend a long time in a crowd.", "extraversion", true},
		{"a1", "I try to understand how other people feel.", "agreeableness", false},
		{"a2", "I am willing to help classmates even when it is inconvenient.", "agreeableness", false},
		{"a3", "I find it hard to take other people's problems seriously.", "agreeableness", true},
		{"a4", "I would rather win an argument than keep the peace.", "agreeableness", true},
		{"c1", "I finish my assignments before the deadline.", "conscientiousness", false},
		{"c2", "I keep my notes and study material organised.", "conscientiousness", false},
		{"c3", "I often leave important tasks until the last minute.", "conscientiousness", true},
		{"c4", "I find it hard to stick to a study plan.", "conscientiousness", true},
		{"s1", "I stay calm when exams or interviews get stressful.", "stability", false},
		{"s2", "I recover quickly after a setback.", "stability", false},
		{"s3", "I worry a lot about things that might go wrong.", "stability", true},
		{"s4", "Small criticisms stay on my mind for a long time.", "stability", true},
		{"o1", "I enjoy learning about topics outside my syllabus.", "openness", false},
		{"o2", "I like finding new ways to solve a problem.", "openness", false},
		{"o3", "I prefer to follow familiar methods rather than try new ones.", "openness", true},
		{"o4", "I lose interest when ideas are abstract or theoretical.", "openness", true},
	},
}

var likeScale = []string{"Strongly dislike", "Dislike", "Neutral", "Like", "Strongly like"}

// interests covers the six Holland (RIASEC) types, then what the student values in a job.
var interests = Questionnaire{
	Kind:  "interests",
	Title: "Interests and values",
	Intro: "First, how much would you enjoy each activity? Then, how important is each thing to you in a job?",
	Scale: likeScale,
	Traits: []Trait{
		{"realistic", "Realistic (hands-on, hardware)"},
		{"investigative", "Investigative (research, analysis)"},
		{"artistic", "Artistic (design, creative)"},
		{"social", "Social (helping, teaching)"},
		{"enterprising", "Enterprising (leading, persuading)"},
		{"conventional", "Conventional (organised, detail)"},
		{"val_salary", "Value: high salary"},
		{"val_security", "Value: job security"},
		{"val_growth", "Value: fast career growth"},
		{"val_creativity", "Value: creative freedom"},
		{"val_helping", "Value: helping others"},
		{"val_autonomy", "Value: independence"},
	},
	Questions: []Question{
		{"r1", "Building or repairing machines or electronic devices", "realistic", false},
		{"r2", "Working with tools and hardware in a lab", "realistic", false},
		{"r3", "Setting up networks or computer equipment", "realistic", false},
		{"r4", "Operating or testing equipment", "realistic", false},
		{"i1", "Analysing data to find patterns", "investigative", false},
		{"i2", "Researching how a technology works", "investigative", false},
		{"i3", "Solving difficult maths or logic problems", "investigative", false},
		{"i4", "Running experiments to test an idea", "investigative", false},
		{"a1", "Designing user interfaces or graphics", "artistic", false},
		{"a2", "Writing, blogging or making videos", "artistic", false},
		{"a3", "Coming up with original ideas for a product", "artistic", false},
		{"a4", "Working in a creative team on something new", "artistic", false},
		{"s1", "Teaching or mentoring other students", "social", false},
		{"s2", "Helping people solve their problems", "social", false},
		{"s3", "Working with customers or clients", "social", false},
		{"s4", "Organising events or community activities", "social", false},
		{"e1", "Leading a team towards a goal", "enterprising", false},
		{"e2", "Persuading others to accept an idea", "enterprising", false},
		{"e3", "Starting a project or a small business", "enterprising", false},
		{"e4", "Negotiating or presenting to senior people", "enterprising", false},
		{"c1", "Keeping records and data accurate and organised", "conventional", false},
		{"c2", "Following clear procedures and checklists", "conventional", false},
		{"c3", "Working with spreadsheets and reports", "conventional", false},
		{"c4", "Planning schedules and managing details", "conventional", false},
		{"v1", "A high salary (how important is it to you?)", "val_salary", false},
		{"v2", "Job security and stability", "val_security", false},
		{"v3", "Fast career growth", "val_growth", false},
		{"v4", "Creative freedom in my work", "val_creativity", false},
		{"v5", "Helping others through my work", "val_helping", false},
		{"v6", "Independence in how I work", "val_autonomy", false},
	},
}

var learning = Questionnaire{
	Kind:  "learning",
	Title: "Learning behaviour",
	Intro: "Think about how you usually study. Choose how well each statement describes your habits.",
	Scale: agreeScale,
	Traits: []Trait{
		{"planning", "Planning"},
		{"consistency", "Consistency"},
		{"practice", "Active practice"},
		{"help", "Asking for help"},
		{"resources", "Using resources"},
	},
	Questions: []Question{
		{"p1", "I make a weekly study plan.", "planning", false},
		{"p2", "I set specific goals before I start studying.", "planning", false},
		{"p3", "I review my mistakes after a test.", "planning", false},
		{"k1", "I study a little every day instead of cramming.", "consistency", false},
		{"k2", "I attend classes and labs regularly.", "consistency", false},
		{"k3", "I often postpone studying until just before exams.", "consistency", true},
		{"a1", "I test myself with questions instead of only re-reading notes.", "practice", false},
		{"a2", "I practise coding or problems regularly.", "practice", false},
		{"h1", "I ask teachers or friends when I do not understand something.", "help", false},
		{"h2", "I study with friends and explain ideas to each other.", "help", false},
		{"r1", "I use online courses and videos besides class material.", "resources", false},
		{"r2", "I make summaries, flashcards or mind maps.", "resources", false},
	},
}

// Questionnaires by kind.
var questionnaires = map[string]*Questionnaire{
	"personality":   &personality,
	"interests":     &interests,
	"learning":      &learning,
	"communication": &communication,
}

// Kinds in display order.
var kinds = []string{"personality", "interests", "learning", "communication"}

// communication is the self-report half of the communication and soft-skills score. A staff rubric is the other
// half (see communication.go); the self-report alone never sets the score.
var communication = Questionnaire{
	Kind:  "communication",
	Title: "Communication and soft skills",
	Intro: "Choose how well each statement describes you. Be honest: a staff member will also rate your communication, and the two views are combined.",
	Scale: agreeScale,
	Traits: []Trait{
		{"speaking", "Speaking"},
		{"writing", "Writing"},
		{"listening", "Listening"},
		{"teamwork", "Teamwork"},
		{"adaptability", "Adaptability"},
	},
	Questions: []Question{
		{"sp1", "I can explain a technical idea clearly to someone who does not know the subject.", "speaking", false},
		{"sp2", "I feel confident speaking in front of a group.", "speaking", false},
		{"sp3", "I often struggle to find the right words when I speak.", "speaking", true},
		{"wr1", "My emails and reports are clear and well organised.", "writing", false},
		{"wr2", "I check my spelling and grammar before sending something.", "writing", false},
		{"wr3", "I find it hard to put my thoughts into writing.", "writing", true},
		{"li1", "I let people finish speaking before I answer.", "listening", false},
		{"li2", "I ask questions to make sure I have understood.", "listening", false},
		{"li3", "My mind often wanders when someone is explaining something.", "listening", true},
		{"tw1", "I share the work fairly in a group project.", "teamwork", false},
		{"tw2", "I help teammates who are behind instead of ignoring it.", "teamwork", false},
		{"tw3", "I prefer to do a group task on my own rather than coordinate.", "teamwork", true},
		{"ad1", "I adjust quickly when plans or requirements change.", "adaptability", false},
		{"ad2", "I am comfortable learning a new tool I have never used.", "adaptability", false},
		{"ad3", "I get upset when something unexpected changes my routine.", "adaptability", true},
	},
}
