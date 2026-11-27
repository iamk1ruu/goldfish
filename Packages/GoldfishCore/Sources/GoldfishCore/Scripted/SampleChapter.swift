import Foundation

/// The built-in chapter taught on first run. Its exam is written by hand and checked
/// by the same validator as cloud exams, so first run needs no connection and no quota.
public enum SampleChapter {
    public static let id = "sample"
    public static let title = "How a Goldfish Lives Underwater"

    public static let text = """
    How a Goldfish Lives Underwater

    Breathing with gills
    A goldfish breathes by pulling oxygen out of water rather than air. Water enters through the mouth and passes over the gills, which sit on both sides of the head. The water then leaves through a bony flap called the operculum, which also protects the gills. Each gill is made of rows of thin filaments, and each filament is covered in tiny folds called lamellae. The lamellae give the gills a huge surface area, and their walls are so thin that oxygen can pass straight from the water into the blood. Carbon dioxide moves the other way, out of the blood and into the water.

    Countercurrent exchange
    Inside the lamellae, blood flows in the opposite direction to the water flowing over them. This arrangement is called countercurrent exchange. Because the two streams run against each other, the blood always meets water that holds a little more oxygen than it does, so oxygen keeps moving into the blood along the whole length of each fold. If the blood and water flowed in the same direction, they would quickly even out and the fish would capture far less oxygen. Countercurrent exchange is the reason fish can breathe in water, which holds much less oxygen than air.

    The swim bladder
    Most bony fish, including goldfish, have a swim bladder: a gas-filled sac inside the body. By changing how much gas the bladder holds, a fish can hover at one depth without swimming, which saves energy. Adding gas makes the fish rise, and letting gas out makes it sink. A goldfish's swim bladder has two chambers and is joined to its gut by a narrow tube, so a goldfish can top up its bladder by gulping air at the surface. Fancy goldfish with short, round bodies often have swim bladder problems and may float upside down or struggle to stay off the bottom.

    The lateral line
    Along each side of a goldfish runs a faint line of tiny pores called the lateral line. Under the pores are clusters of sensory cells called neuromasts, which carry tiny hairs. When the water moves, the hairs bend, and the fish feels the movement. The lateral line lets a goldfish sense nearby fish, predators and obstacles even in dark or muddy water. It also helps fish in a group keep their distance from one another as they swim together.

    Living in fresh water
    A goldfish's body fluids are saltier than the fresh water it lives in. Because of this, water constantly seeps into its body by osmosis, mostly through the gills. To avoid swelling up, a freshwater fish hardly ever drinks and makes large amounts of very dilute urine to get rid of the extra water. It also takes in salt from the water through special cells in its gills, to replace the salt lost in its urine. Saltwater fish face the opposite problem: they lose water to the sea, so they drink seawater and pump the extra salt out through their gills.

    Temperature and oxygen
    Goldfish are ectotherms, which means their body temperature matches the water around them. In warm water a goldfish's metabolism speeds up: it swims more, eats more and needs more oxygen. In cold water everything slows down. Warm water holds less dissolved oxygen than cold water, so on a hot summer day a goldfish needs more oxygen just when the water holds less. In winter, pond goldfish can survive under ice by becoming sluggish and barely eating until spring.
    """

    public static func chapter(createdAt: Date) -> Chapter {
        Chapter(id: id, title: title, sourceText: text, createdAt: createdAt, isSample: true)
    }

    public static func exam(compiledAt: Date) -> Exam {
        ExamValidator.build(
            draft: draft, chapterID: id, chapterText: text,
            compiledBy: "hand-written", compiledAt: compiledAt
        ).exam
    }

    /// Correct options are listed first here. The validator spreads them across A to D.
    public static let draft = ExamDraft(concepts: [
        ConceptDraft(
            name: "Breathing with gills",
            summary: "Gills pull oxygen out of water that flows in through the mouth and out under the operculum.",
            whyQuestion: "Why do gills need such a huge surface area?",
            questions: [
                q("practice", "Through which structure does water leave a goldfish's gills?",
                  ["Operculum", "Nostril", "Swim bladder", "Lateral line"],
                  ["operculum", "nostril", "bladder", "lateral"],
                  "Water flows out past the gills through a flap called the operculum.",
                  "The water then leaves through a bony flap called the operculum, which also protects the gills.",
                  "Water leaves through the operculum, the bony flap over the gills."),
                q("practice", "What are the tiny folds on gill filaments called?",
                  ["Lamellae", "Scales", "Neuromasts", "Villi"],
                  ["lamella", "scale", "neuromast", "villi"],
                  "The gill filaments are covered in tiny folds called lamellae.",
                  "each filament is covered in tiny folds called lamellae",
                  "Each gill filament is covered in tiny folds called lamellae."),
                q("practice", "Which gas passes from the water into a goldfish's blood at the gills?",
                  ["Oxygen", "Nitrogen", "Carbon dioxide", "Helium"],
                  ["oxygen", "nitrogen", "carbon", "helium"],
                  "Oxygen passes from the water into the blood through the thin gill walls.",
                  "oxygen can pass straight from the water into the blood",
                  "Oxygen moves into the blood. Carbon dioxide moves out."),
                q("final", "Why can oxygen pass so easily into the blood at the gills?",
                  ["Their walls are very thin", "They are full of air", "They are coated in mucus", "They pump water with muscles"],
                  ["thin", "air", "mucus", "muscle"],
                  "Oxygen can pass into the blood easily because the gill walls are very thin.",
                  "their walls are so thin that oxygen can pass straight from the water into the blood",
                  "The lamellae walls are so thin that oxygen passes straight into the blood."),
                q("yourTurn", "What does the operculum do besides letting water out?",
                  ["Protects the gills", "Stores food", "Senses sound", "Makes mucus"],
                  ["protect", "food", "sound", "mucus"],
                  "Besides letting water out, the operculum protects the gills.",
                  "a bony flap called the operculum, which also protects the gills",
                  "The operculum also protects the gills."),
            ]
        ),
        ConceptDraft(
            name: "Countercurrent exchange",
            summary: "Blood and water flow in opposite directions, so oxygen keeps moving into the blood.",
            whyQuestion: "Why would a fish get less oxygen if blood and water flowed the same way?",
            questions: [
                q("practice", "In the lamellae, which way does blood flow compared with the water?",
                  ["Opposite direction", "Same direction", "At right angles", "Only when resting"],
                  ["opposite", "same", "right angle", "resting"],
                  "Blood in the lamellae flows the opposite way to the water.",
                  "blood flows in the opposite direction to the water flowing over them",
                  "Blood flows in the opposite direction to the water."),
                q("practice", "What is the name for blood and water flowing against each other in the gills?",
                  ["Countercurrent exchange", "Osmosis", "Photosynthesis", "Buoyancy"],
                  ["countercurrent", "osmosis", "photosynth", "buoyan"],
                  "Blood and water running against each other in the gills is called countercurrent exchange.",
                  "This arrangement is called countercurrent exchange",
                  "The arrangement is called countercurrent exchange."),
                q("practice", "What would happen if blood and water flowed the same way through the gills?",
                  ["The fish would capture far less oxygen", "The fish would float to the top", "The gills would freeze", "The blood would turn salty"],
                  ["less oxygen", "float", "freeze", "salty"],
                  "If blood and water flowed the same way, the fish would get much less oxygen.",
                  "the fish would capture far less oxygen",
                  "Flowing the same way, the two would even out and the fish would get less oxygen."),
                q("final", "Why does blood keep picking up oxygen along the whole fold?",
                  ["It always meets water with a little more oxygen", "The fold is coated in sugar", "The heart stops between beats", "The water is warmer than the blood"],
                  ["more oxygen", "sugar", "heart", "warmer"],
                  "Because the flows run against each other, the blood always meets water with more oxygen than it has.",
                  "the blood always meets water that holds a little more oxygen than it does",
                  "The blood always meets water holding a little more oxygen than it does."),
                q("yourTurn", "Along how much of each fold does oxygen keep entering the blood?",
                  ["The whole length", "Only the tip", "Only the base", "Only the middle"],
                  ["whole", "tip", "base", "middle"],
                  "Oxygen keeps moving into the blood along the whole length of each fold.",
                  "oxygen keeps moving into the blood along the whole length of each fold",
                  "Countercurrent flow keeps oxygen moving in along the whole fold."),
            ]
        ),
        ConceptDraft(
            name: "The swim bladder",
            summary: "A gas-filled sac lets a fish hover at one depth without swimming.",
            whyQuestion: "Why does hovering with a swim bladder save energy?",
            questions: [
                q("practice", "What lets a goldfish hover at one depth without swimming?",
                  ["Swim bladder", "Lateral line", "Operculum", "Kidneys"],
                  ["bladder", "lateral", "operculum", "kidney"],
                  "The swim bladder is a gas sac that lets the fish hover without swimming.",
                  "a fish can hover at one depth without swimming",
                  "Changing the gas in the swim bladder lets a fish hover without swimming."),
                q("practice", "What happens when a goldfish adds gas to its swim bladder?",
                  ["It rises", "It sinks", "It turns around", "It breathes faster"],
                  ["rise", "sink", "turn", "faster"],
                  "Putting more gas into the swim bladder makes the fish rise.",
                  "Adding gas makes the fish rise",
                  "Adding gas makes the fish rise, and letting it out makes it sink."),
                q("practice", "How can a goldfish top up its swim bladder?",
                  ["By gulping air at the surface", "By eating plants", "By sleeping", "By drinking salt water"],
                  ["gulp", "plant", "sleep", "salt"],
                  "A goldfish can fill its swim bladder by gulping air at the surface.",
                  "a goldfish can top up its bladder by gulping air at the surface",
                  "The bladder is joined to the gut, so the fish can gulp air to fill it."),
                q("final", "What joins a goldfish's swim bladder to its gut?",
                  ["A narrow tube", "A gill arch", "A blood vessel", "A bone"],
                  ["tube", "gill", "vessel", "bone"],
                  "A narrow tube connects the swim bladder to the gut.",
                  "is joined to its gut by a narrow tube",
                  "A narrow tube joins the swim bladder to the gut."),
                q("yourTurn", "Why do fancy goldfish often float upside down?",
                  ["They have swim bladder problems", "They are asleep", "They are cold", "They are full of food"],
                  ["bladder", "asleep", "cold", "food"],
                  "Fancy goldfish often have swim bladder problems, so they can float upside down.",
                  "Fancy goldfish with short, round bodies often have swim bladder problems",
                  "Short, round fancy goldfish often have swim bladder problems."),
            ]
        ),
        ConceptDraft(
            name: "The lateral line",
            summary: "A line of pores with sensory hairs lets a fish feel movement in the water.",
            whyQuestion: "How does a bending hair tell a fish that something is nearby?",
            questions: [
                q("practice", "Which sense organ lets a goldfish feel water moving around it?",
                  ["Lateral line", "Swim bladder", "Operculum", "Gill filaments"],
                  ["lateral", "bladder", "operculum", "filament"],
                  "The lateral line lets the fish feel the water moving around it.",
                  "When the water moves, the hairs bend, and the fish feels the movement",
                  "The lateral line senses movement in the water."),
                q("practice", "What are the clusters of sensory cells under the lateral line pores called?",
                  ["Neuromasts", "Lamellae", "Scales", "Taste buds"],
                  ["neuromast", "lamella", "scale", "taste"],
                  "Under the pores sit sensory cells called neuromasts.",
                  "clusters of sensory cells called neuromasts",
                  "The sensory cells under the pores are called neuromasts."),
                q("practice", "What happens to the tiny hairs when the water moves?",
                  ["They bend", "They fall out", "They glow", "They grow longer"],
                  ["bend", "fall", "glow", "grow"],
                  "When water moves, the tiny hairs bend.",
                  "When the water moves, the hairs bend",
                  "Moving water bends the hairs, and the fish feels it."),
                q("final", "When is the lateral line especially useful?",
                  ["In dark or muddy water", "Only when eating", "When the fish is out of water", "Only in bright sunlight"],
                  ["muddy", "eating", "out of water", "sunlight"],
                  "The lateral line lets a goldfish find its way even in dark, muddy water.",
                  "even in dark or muddy water",
                  "It works even when the fish cannot see, in dark or muddy water."),
                q("yourTurn", "How does the lateral line help fish swimming in a group?",
                  ["It helps them keep their distance", "It helps them sleep", "It helps them change colour", "It helps them lay eggs"],
                  ["distance", "sleep", "colour", "eggs"],
                  "In a group, the lateral line helps each fish keep its distance from the others.",
                  "helps fish in a group keep their distance from one another",
                  "Fish in a group use it to keep their distance."),
            ]
        ),
        ConceptDraft(
            name: "Living in fresh water",
            summary: "Water seeps in by osmosis, so a goldfish rarely drinks and makes dilute urine.",
            whyQuestion: "Why does a goldfish hardly ever drink, even though it lives in water?",
            questions: [
                q("practice", "Why does water keep seeping into a goldfish's body?",
                  ["Its body fluids are saltier than the water", "It swims with its mouth open", "Its scales soak it up", "It is always thirsty"],
                  ["saltier", "mouth", "scale", "thirsty"],
                  "Water keeps seeping into a goldfish's body because its body fluids are saltier.",
                  "A goldfish's body fluids are saltier than the fresh water it lives in",
                  "Saltier body fluids draw water in by osmosis."),
                q("practice", "How does a freshwater fish get rid of extra water?",
                  ["Very dilute urine", "Sweating", "Breathing it out", "Crying"],
                  ["urine", "sweat", "breath", "cry"],
                  "It gets rid of the extra water by making lots of very dilute urine.",
                  "makes large amounts of very dilute urine to get rid of the extra water",
                  "It makes large amounts of very dilute urine."),
                q("practice", "Through what does a goldfish take in salt from the water?",
                  ["Special cells in its gills", "Its eyes", "Its tail fin", "Its swim bladder"],
                  ["gill", "eye", "tail", "bladder"],
                  "Special cells in the gills take in salt from the water.",
                  "takes in salt from the water through special cells in its gills",
                  "Special gill cells take in salt to replace what is lost in urine."),
                q("final", "How often does a freshwater fish drink?",
                  ["Hardly ever", "Constantly", "Only at night", "Once an hour"],
                  ["hardly", "constant", "night", "hour"],
                  "A freshwater fish will hardly ever drink.",
                  "a freshwater fish hardly ever drinks",
                  "Water already seeps in, so a freshwater fish hardly ever drinks."),
                q("yourTurn", "What do saltwater fish do with the extra salt from seawater?",
                  ["Pump it out through their gills", "Store it in their bones", "Turn it into sugar", "Keep it in their swim bladder"],
                  ["pump", "bone", "sugar", "bladder"],
                  "Saltwater fish pump the extra salt out through their gills.",
                  "pump the extra salt out through their gills",
                  "Saltwater fish drink seawater and pump the salt out through their gills."),
            ]
        ),
        ConceptDraft(
            name: "Temperature and oxygen",
            summary: "A goldfish's body matches the water's temperature, and warm water holds less oxygen.",
            whyQuestion: "Why does warm water make life harder for a goldfish?",
            questions: [
                q("practice", "Goldfish are ectotherms. What does that mean for their body temperature?",
                  ["Their body temperature matches the water", "They make their own heat", "They can live out of water", "They never sleep"],
                  ["matches", "heat", "live out", "sleep"],
                  "Being an ectotherm means a goldfish's body temperature matches the water around it.",
                  "their body temperature matches the water around them",
                  "An ectotherm's body temperature matches its surroundings."),
                q("practice", "What happens to a goldfish's metabolism in warm water?",
                  ["It speeds up", "It stops", "It slows down", "It stays the same"],
                  ["speeds up", "stop", "slows", "same"],
                  "In warm water a goldfish's metabolism speeds up.",
                  "In warm water a goldfish's metabolism speeds up",
                  "Warm water speeds up metabolism, so the fish swims and eats more."),
                q("practice", "Which holds more dissolved oxygen, warm water or cold water?",
                  ["Cold water", "Warm water", "Both hold the same", "Neither holds any"],
                  ["cold", "warm", "same", "neither"],
                  "Cold water can hold more dissolved oxygen.",
                  "Warm water holds less dissolved oxygen than cold water",
                  "Cold water holds more dissolved oxygen than warm water."),
                q("final", "Why is a hot summer day hard on a goldfish?",
                  ["It needs more oxygen while the water holds less", "Its scales melt", "Sunlight blinds it", "It forgets where food is"],
                  ["needs more oxygen", "melt", "blind", "forget"],
                  "On a hot summer day a goldfish needs more oxygen, but the warm water holds less.",
                  "a goldfish needs more oxygen just when the water holds less",
                  "In summer the fish needs more oxygen just when the water holds less."),
                q("yourTurn", "How do pond goldfish survive under ice in winter?",
                  ["They become sluggish and barely eat", "They migrate south", "They bury themselves in sand", "They grow thicker scales"],
                  ["sluggish", "migrate", "sand", "thicker"],
                  "Under ice in winter, pond goldfish turn sluggish and barely eat.",
                  "becoming sluggish and barely eating until spring",
                  "They slow right down and barely eat until spring."),
            ]
        ),
    ])

    /// A partly taught lesson for screenshots and tests: two sections taught well, one with a
    /// planted mistake (adding gas makes the fish "sink"), one partly taught, two left empty.
    public static func fixtureSections(exam: Exam) -> [String: String] {
        let texts = [
            "Water goes in through the mouth, over the gills, and out through a flap called the operculum. The gill filaments are covered in tiny folds called lamellae. Oxygen passes from the water into the blood through the thin gill walls.",
            "Blood in the lamellae flows the opposite way to the water. That setup is called countercurrent exchange.",
            "The swim bladder is a gas sac that lets the fish hover without swimming. Adding gas to the swim bladder makes the fish sink.",
            "",
            "Goldfish body fluids are saltier than fresh water, so water seeps in. It gets rid of the extra water by making lots of very dilute urine.",
            "",
        ]
        var sections: [String: String] = [:]
        for (index, concept) in exam.concepts.enumerated() where index < texts.count {
            sections[concept.id] = texts[index]
        }
        return sections
    }

    private static func q(
        _ pool: String, _ stem: String, _ options: [String], _ keys: [String],
        _ modelSentence: String, _ sourceQuote: String, _ explanation: String
    ) -> QuestionDraft {
        QuestionDraft(
            pool: pool, stem: stem, options: options, correctIndex: 0, keyTerms: keys,
            explanation: explanation, sourceQuote: sourceQuote, modelSentence: modelSentence
        )
    }
}
