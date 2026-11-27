import Foundation

/// One question in the Fish Check, with the sentence a student might write to teach it.
public struct FidelityItem: Equatable {
    public let id: String
    public let question: String
    public let options: [String]
    /// Lowercase stems, one per option, used to check that a quote supports that option.
    public let keys: [String]
    public let correct: Int
    /// The wrong option that `wrongSentence` teaches.
    public let planted: Int
    public let sentence: String
    public let wrongSentence: String
}

/// Twenty cell-biology facts that a language model very likely already knows.
/// Well-known facts make the check harsh: if the model leans on what it knows, it shows.
/// Ported from an earlier Chrome test, since deleted from the repo. Each correct key appears only in
/// its own sentence, which the tests enforce.
public enum FidelityDataset {
    public static let items: [FidelityItem] = [
        FidelityItem(
            id: "atp",
            question: "Which organelle produces most of the ATP in a eukaryotic cell?",
            options: ["Ribosome", "Mitochondrion", "Golgi apparatus", "Lysosome"],
            keys: ["ribosome", "mitochondri", "golgi", "lysosome"],
            correct: 1,
            planted: 2,
            sentence: "Mitochondria are basically the power plants, they crank out most of the cell's ATP.",
            wrongSentence: "Golgi bodies are basically the power plants, they crank out most of the cell's ATP."
        ),
        FidelityItem(
            id: "protein",
            question: "Which structure links amino acids together into a protein chain?",
            options: ["Ribosome", "Peroxisome", "Centriole", "Vacuole"],
            keys: ["ribosome", "peroxisome", "centriole", "vacuole"],
            correct: 0,
            planted: 2,
            sentence: "Ribosomes are the little factories that stitch amino acids together one at a time.",
            wrongSentence: "Centrioles are the little factories that stitch amino acids together one at a time."
        ),
        FidelityItem(
            id: "recycling",
            question: "Which organelle uses digestive enzymes to break down worn-out cell parts?",
            options: ["Chloroplast", "Vacuole", "Lysosome", "Nucleus"],
            keys: ["chloroplast", "vacuole", "lysosome", "nucleus"],
            correct: 2,
            planted: 1,
            sentence: "Lysosomes are the recycling crew, their enzymes chew up old broken parts.",
            wrongSentence: "Vacuoles are the recycling crew, their enzymes chew up old broken parts."
        ),
        FidelityItem(
            id: "packaging",
            question: "Which organelle modifies proteins and packages them for delivery?",
            options: ["Smooth ER", "Nucleus", "Peroxisome", "Golgi apparatus"],
            keys: ["smooth", "nucleus", "peroxisome", "golgi"],
            correct: 3,
            planted: 0,
            sentence: "The Golgi is the post office, it tags proteins, boxes them up and ships them out.",
            wrongSentence: "The smooth ER is the post office, it tags proteins, boxes them up and ships them out."
        ),
        FidelityItem(
            id: "dna-store",
            question: "Where is nearly all of a human cell's genetic material kept?",
            options: ["Cytoplasm", "Nucleus", "Centriole", "Vacuole"],
            keys: ["cytoplasm", "nucleus", "centriole", "vacuole"],
            correct: 1,
            planted: 0,
            sentence: "The nucleus is the vault where almost all of the DNA is locked away.",
            wrongSentence: "The cytoplasm is the vault where almost all of the DNA is locked away."
        ),
        FidelityItem(
            id: "photosynthesis",
            question: "In plant cells, which organelle captures light energy to make sugar?",
            options: ["Chloroplast", "Mitochondrion", "Ribosome", "Lysosome"],
            keys: ["chloroplast", "mitochondri", "ribosome", "lysosome"],
            correct: 0,
            planted: 1,
            sentence: "Chloroplasts are the solar panels, they soak up sunlight and turn it into sugar.",
            wrongSentence: "Mitochondria are the solar panels, they soak up sunlight and turn it into sugar."
        ),
        FidelityItem(
            id: "turgor",
            question: "Which part of a mature plant cell stores water and keeps the cell firm?",
            options: ["Nucleolus", "Peroxisome", "Chloroplast", "Central vacuole"],
            keys: ["nucleolus", "peroxisome", "chloroplast", "vacuole"],
            correct: 3,
            planted: 1,
            sentence: "The big vacuole is a water balloon that pushes outward and stops a plant from wilting.",
            wrongSentence: "The big peroxisome is a water balloon that pushes outward and stops a plant from wilting."
        ),
        FidelityItem(
            id: "plant-wall",
            question: "Which carbohydrate gives plant cell walls their strength?",
            options: ["Glycogen", "Starch", "Cellulose", "Chitin"],
            keys: ["glycogen", "starch", "cellulose", "chitin"],
            correct: 2,
            planted: 0,
            sentence: "Cellulose is the tough fiber that makes plant walls so sturdy.",
            wrongSentence: "Glycogen is the tough fiber that makes plant walls so sturdy."
        ),
        FidelityItem(
            id: "spindle",
            question: "Which protein filaments form the spindle during cell division?",
            options: ["Intermediate filaments", "Microtubules", "Actin filaments", "Collagen fibers"],
            keys: ["intermediate", "microtubule", "actin", "collagen"],
            correct: 1,
            planted: 0,
            sentence: "Microtubules are the ropes that drag the chromosomes to each end when a cell splits.",
            wrongSentence: "Intermediate filaments are the ropes that drag the chromosomes to each end when a cell splits."
        ),
        FidelityItem(
            id: "membrane",
            question: "Which molecules form the basic double layer of a cell membrane?",
            options: ["Triglycerides", "Glycoproteins", "Nucleotides", "Phospholipids"],
            keys: ["triglyceride", "glycoprotein", "nucleotide", "phospholipid"],
            correct: 3,
            planted: 0,
            sentence: "Phospholipids line up in two sheets, tails in and heads out, and that is the skin of the cell.",
            wrongSentence: "Triglycerides line up in two sheets, tails in and heads out, and that is the skin of the cell."
        ),
        FidelityItem(
            id: "detox",
            question: "Which organelle makes lipids and detoxifies drugs in liver cells?",
            options: ["Smooth ER", "Rough ER", "Ribosome", "Nucleolus"],
            keys: ["smooth", "rough", "ribosome", "nucleolus"],
            correct: 0,
            planted: 1,
            sentence: "Smooth ER has no bumps, it builds fats and cleans toxins out of liver cells.",
            wrongSentence: "Rough ER has no bumps, it builds fats and cleans toxins out of liver cells."
        ),
        FidelityItem(
            id: "peroxide",
            question: "Which organelle specializes in breaking down hydrogen peroxide?",
            options: ["Lysosome", "Peroxisome", "Golgi apparatus", "Nucleus"],
            keys: ["lysosome", "peroxisome", "golgi", "nucleus"],
            correct: 1,
            planted: 0,
            sentence: "Peroxisomes deal with the bleach-like hydrogen peroxide so it cannot hurt anything.",
            wrongSentence: "Lysosomes deal with the bleach-like hydrogen peroxide so it cannot hurt anything."
        ),
        FidelityItem(
            id: "chromatids",
            question: "During which phase of mitosis do sister chromatids separate?",
            options: ["Prophase", "Metaphase", "Anaphase", "Telophase"],
            keys: ["prophase", "metaphase", "anaphase", "telophase"],
            correct: 2,
            planted: 1,
            sentence: "Anaphase is when the sister chromatids finally get ripped apart.",
            wrongSentence: "Metaphase is when the sister chromatids finally get ripped apart."
        ),
        FidelityItem(
            id: "glucose-split",
            question: "Which pathway converts one glucose molecule into two pyruvate molecules?",
            options: ["Krebs cycle", "Calvin cycle", "Electron transport chain", "Glycolysis"],
            keys: ["krebs", "calvin", "electron transport", "glycolysis"],
            correct: 3,
            planted: 0,
            sentence: "Glycolysis happens out in the cytosol and snaps one glucose into two pyruvates.",
            wrongSentence: "The Krebs cycle happens out in the cytosol and snaps one glucose into two pyruvates."
        ),
        FidelityItem(
            id: "acetyl",
            question: "Which stage of cellular respiration oxidizes acetyl-CoA and releases carbon dioxide?",
            options: ["Krebs cycle", "Calvin cycle", "Glycolysis", "Fermentation"],
            keys: ["krebs", "calvin", "glycolysis", "fermentation"],
            correct: 0,
            planted: 1,
            sentence: "The Krebs cycle spins inside the matrix, burning acetyl groups and breathing out CO2.",
            wrongSentence: "The Calvin cycle spins inside the matrix, burning acetyl groups and breathing out CO2."
        ),
        FidelityItem(
            id: "water-move",
            question: "What is the movement of water across a selectively permeable membrane called?",
            options: ["Endocytosis", "Exocytosis", "Osmosis", "Active transport"],
            keys: ["endocytosis", "exocytosis", "osmosis", "active transport"],
            correct: 2,
            planted: 0,
            sentence: "Osmosis is just water sneaking through a barrier toward the saltier side.",
            wrongSentence: "Endocytosis is just water sneaking through a barrier toward the saltier side."
        ),
        FidelityItem(
            id: "ion-balance",
            question: "Which membrane protein spends ATP to keep sodium low and potassium high inside a cell?",
            options: ["Aquaporin", "Sodium-potassium pump", "Ligand-gated channel", "ATP synthase"],
            keys: ["aquaporin", "pump", "channel", "synthase"],
            correct: 1,
            planted: 3,
            sentence: "The sodium-potassium pump spends energy to shove three sodium out and pull two potassium in.",
            wrongSentence: "ATP synthase spends energy to shove three sodium out and pull two potassium in."
        ),
        FidelityItem(
            id: "swimming",
            question: "Which structures do many bacteria use to swim?",
            options: ["Pili", "Capsule", "Plasmids", "Flagella"],
            keys: ["pili", "capsule", "plasmid", "flagell"],
            correct: 3,
            planted: 0,
            sentence: "Flagella are whip-like tails that let bacteria zip around.",
            wrongSentence: "Pili are whip-like tails that let bacteria zip around."
        ),
        FidelityItem(
            id: "extra-dna",
            question: "What is the small circular piece of extra DNA often found in bacteria?",
            options: ["Nucleoid", "Capsid", "Plasmid", "Intron"],
            keys: ["nucleoid", "capsid", "plasmid", "intron"],
            correct: 2,
            planted: 0,
            sentence: "Plasmids are tiny rings of bonus DNA that bacteria can pass to each other.",
            wrongSentence: "Nucleoids are tiny rings of bonus DNA that bacteria can pass to each other."
        ),
        FidelityItem(
            id: "gene-copy",
            question: "What process copies a gene from DNA into messenger RNA?",
            options: ["Transcription", "Replication", "Translation", "Splicing"],
            keys: ["transcription", "replication", "translation", "splicing"],
            correct: 0,
            planted: 2,
            sentence: "Transcription is when a gene gets copied out of DNA into an mRNA note.",
            wrongSentence: "Translation is when a gene gets copied out of DNA into an mRNA note."
        ),
    ]
}
