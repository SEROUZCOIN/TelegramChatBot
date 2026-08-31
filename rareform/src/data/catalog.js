// The catalogue drives geometry, not just copy: `kind`, `fit` and `fabric` are
// fed straight into the garment builder, so adding a product adds a 3D model.

export const DEPARTMENTS = ['Women', 'Men', 'Unisex']

export const CATEGORIES = [
  { id: 'tshirts', label: 'T-Shirts', kind: 'tee', group: 'Tops' },
  { id: 'shirts', label: 'Shirts', kind: 'shirt', group: 'Tops' },
  { id: 'hoodies', label: 'Hoodies', kind: 'hoodie', group: 'Tops' },
  { id: 'knitwear', label: 'Knitwear', kind: 'sweater', group: 'Tops' },
  { id: 'jackets', label: 'Jackets', kind: 'jacket', group: 'Outerwear' },
  { id: 'coats', label: 'Coats', kind: 'coat', group: 'Outerwear' },
  { id: 'trousers', label: 'Trousers', kind: 'pants', group: 'Bottoms' },
  { id: 'jeans', label: 'Denim', kind: 'jeans', group: 'Bottoms' },
  { id: 'shorts', label: 'Shorts', kind: 'shorts', group: 'Bottoms' },
  { id: 'dresses', label: 'Dresses', kind: 'dress', group: 'Womenswear' },
  { id: 'skirts', label: 'Skirts', kind: 'skirt', group: 'Womenswear' },
  { id: 'footwear', label: 'Footwear', kind: 'sneaker', group: 'Accessories' },
  { id: 'headwear', label: 'Headwear', kind: 'cap', group: 'Accessories' },
  { id: 'bags', label: 'Bags', kind: 'tote', group: 'Accessories' },
  { id: 'accessories', label: 'Accessories', kind: 'scarf', group: 'Accessories' },
]

export const CATEGORY_GROUPS = ['Tops', 'Outerwear', 'Bottoms', 'Womenswear', 'Accessories']

export const SIZE_SETS = {
  apparel: ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL'],
  waist: ['26', '28', '30', '32', '34', '36', '38'],
  shoe: ['UK5', 'UK6', 'UK7', 'UK8', 'UK9', 'UK10', 'UK11'],
  one: ['One size'],
}

export const COLOR_FAMILIES = [
  { id: 'black', label: 'Black', swatch: '#16181a' },
  { id: 'white', label: 'White', swatch: '#efece2' },
  { id: 'grey', label: 'Grey', swatch: '#8d918c' },
  { id: 'brown', label: 'Brown', swatch: '#7a5a41' },
  { id: 'green', label: 'Green', swatch: '#4d6a4a' },
  { id: 'blue', label: 'Blue', swatch: '#3d5878' },
  { id: 'red', label: 'Red', swatch: '#9c3b34' },
  { id: 'neutral', label: 'Neutral', swatch: '#c9bda6' },
  { id: 'accent', label: 'Accent', swatch: '#ceff25' },
]

const c = (name, hex, family, accent) => ({ name, hex, family, accent: accent ?? hex })

const INK = c('Ink', '#191b1c', 'black')
const VOID_ = c('Void', '#0a0c0b', 'black')
const BONE = c('Bone', '#ded7c6', 'white', '#c9c1ad')
const CHALK = c('Chalk', '#eae6dc', 'white')
const GRAPHITE = c('Graphite', '#3c4040', 'grey')
const ASH = c('Ash', '#9a9d97', 'grey')
const CLAY = c('Clay', '#b2745a', 'brown')
const TOBACCO = c('Tobacco', '#6d4c33', 'brown')
const MOSS = c('Moss', '#4f5f42', 'green')
const SAGE = c('Sage', '#93a48b', 'green')
const SLATE = c('Slate', '#4a5a6b', 'blue')
const INDIGO = c('Indigo', '#2f4260', 'blue')
const WASHED = c('Washed Indigo', '#6d87a8', 'blue')
const OXBLOOD = c('Oxblood', '#6d2f2c', 'red')
const EMBER = c('Ember', '#b4503c', 'red')
const SAND = c('Sand', '#c8b494', 'neutral')
const OAT = c('Oat', '#d5c9ae', 'neutral')
const CHARTREUSE = c('Signal', '#c8f52c', 'accent', '#101210')

let counter = 0

function product(config) {
  counter += 1
  const category = CATEGORIES.find(cat => cat.id === config.category)
  const sizeSet = config.sizes ?? 'apparel'
  return {
    id: config.id ?? `rf-${String(counter).padStart(3, '0')}`,
    sku: `RF-${category.id.slice(0, 3).toUpperCase()}-${String(counter).padStart(3, '0')}`,
    name: config.name,
    category: category.id,
    categoryLabel: category.label,
    group: category.group,
    department: config.department ?? 'Unisex',
    kind: config.kind ?? category.kind,
    fit: config.fit ?? 'regular',
    fabric: config.fabric,
    materialLabel: config.materialLabel,
    price: config.price,
    compareAt: config.compareAt ?? null,
    colorways: config.colorways,
    sizes: SIZE_SETS[sizeSet],
    sizeType: sizeSet,
    stock: config.stock ?? 18,
    rating: config.rating ?? 4.6,
    reviews: config.reviews ?? 40,
    popularity: config.popularity ?? 50,
    releasedAt: config.releasedAt ?? '2026-02-01',
    description: config.description,
    details: config.details ?? [],
    care: config.care ?? 'Cold machine wash, dry flat, warm iron on reverse.',
    tags: config.tags ?? [],
    badge: config.badge ?? null,
    sustainable: config.sustainable ?? false,
    seed: config.seed ?? counter * 7 + 3,
  }
}

export const PRODUCTS = [
  product({
    name: 'Form 01 Heavy Tee', category: 'tshirts', department: 'Unisex', fit: 'oversized',
    fabric: 'jersey', materialLabel: '280gsm combed cotton jersey', price: 48, compareAt: 64,
    colorways: [BONE, INK, MOSS, CHARTREUSE], stock: 64, rating: 4.8, reviews: 412, popularity: 98,
    releasedAt: '2026-01-12', badge: 'Bestseller', sustainable: true,
    description: 'A dense box-cut essential with dropped shoulders and a clean self-collar. The one we build every season on.',
    details: ['Boxy oversized body', 'Dropped shoulder seam', 'Ribbed self-collar', 'Garment dyed'],
    tags: ['everyday', 'heavyweight', 'boxy', 'core'],
  }),
  product({
    name: 'Void Tech Tee', category: 'tshirts', department: 'Unisex', fit: 'relaxed',
    fabric: 'nylon', materialLabel: '320gsm panelled tech jersey', price: 72,
    colorways: [VOID_, GRAPHITE, SLATE], stock: 24, rating: 4.7, reviews: 128, popularity: 88,
    releasedAt: '2026-03-04', badge: '3D Edition',
    description: 'A panel-cut technical tee with articulated sleeves and a sculpted body that holds its shape.',
    details: ['Articulated sleeve panels', 'Bonded hem', 'Matte technical face'],
    tags: ['technical', 'sculpted', 'performance'],
  }),
  product({
    name: 'Portal Slub Tee', category: 'tshirts', department: 'Women', fit: 'cropped',
    fabric: 'cotton', materialLabel: '180gsm slub cotton', price: 42,
    colorways: [CHALK, SAND, EMBER, SAGE], stock: 51, rating: 4.5, reviews: 233, popularity: 74,
    releasedAt: '2026-02-18', sustainable: true,
    description: 'A cropped slub tee with a soft hand and a slightly open weave that moves with you.',
    details: ['Cropped length', 'Slub texture', 'Twin-needle hem'], tags: ['cropped', 'soft', 'summer'],
  }),
  product({
    name: 'Baseline Pocket Tee', category: 'tshirts', department: 'Men', fit: 'regular',
    fabric: 'cotton', materialLabel: '220gsm organic cotton', price: 38,
    colorways: [ASH, INK, INDIGO, OAT], stock: 88, rating: 4.4, reviews: 310, popularity: 66,
    releasedAt: '2025-11-02', sustainable: true,
    description: 'Straight-cut, chest pocket, no noise. The tee you stop thinking about.',
    details: ['Patch chest pocket', 'Straight body', 'Pre-shrunk'], tags: ['basic', 'pocket', 'value'],
  }),
  product({
    name: 'Longline Rib Tee', category: 'tshirts', department: 'Women', fit: 'slim',
    fabric: 'knit', materialLabel: 'Fine rib cotton blend', price: 46,
    colorways: [BONE, OXBLOOD, GRAPHITE], stock: 33, rating: 4.6, reviews: 96, popularity: 61,
    releasedAt: '2026-04-01',
    description: 'A close, elongated rib tee that layers flat under everything.',
    details: ['2x2 fine rib', 'Longline hem', 'Stretch recovery'], tags: ['rib', 'layering', 'longline'],
  }),

  product({
    name: 'Airweight Camp Shirt', category: 'shirts', department: 'Unisex', fit: 'relaxed',
    fabric: 'cotton', materialLabel: 'Washed cotton poplin', price: 78,
    colorways: [CHALK, SAGE, SLATE, SAND], stock: 42, rating: 4.7, reviews: 174, popularity: 81,
    releasedAt: '2026-03-20', badge: 'New', sustainable: true,
    description: 'An open-collar shirt with a soft drape, hidden placket and curved side seams.',
    details: ['Camp collar', 'Hidden placket', 'Curved hem'], tags: ['summer', 'resort', 'drapey'],
  }),
  product({
    name: 'Structure Oxford', category: 'shirts', department: 'Men', fit: 'regular',
    fabric: 'canvas', materialLabel: 'Heavy oxford cotton', price: 92, compareAt: 118,
    colorways: [CHALK, INDIGO, ASH], stock: 27, rating: 4.8, reviews: 205, popularity: 79,
    releasedAt: '2025-10-14',
    description: 'A weighty oxford with a rolled button-down collar that holds a crease all day.',
    details: ['Button-down collar', 'Single-needle side seams', 'Split back yoke'],
    tags: ['oxford', 'workwear', 'structured'],
  }),
  product({
    name: 'Liquid Silk Shirt', category: 'shirts', department: 'Women', fit: 'relaxed',
    fabric: 'silk', materialLabel: '19mm sandwashed silk', price: 186,
    colorways: [OAT, OXBLOOD, VOID_], stock: 12, rating: 4.9, reviews: 61, popularity: 72,
    releasedAt: '2026-04-22', badge: 'Limited',
    description: 'Sandwashed silk with a fluid fall and a collar that stays soft against the neck.',
    details: ['Sandwashed finish', 'French seams', 'Shell buttons'],
    care: 'Dry clean or cold hand wash, line dry away from light.',
    tags: ['silk', 'evening', 'luxury'],
  }),
  product({
    name: 'Grid Overshirt', category: 'shirts', department: 'Unisex', fit: 'oversized',
    fabric: 'corduroy', materialLabel: '8-wale cotton corduroy', price: 128,
    colorways: [TOBACCO, MOSS, GRAPHITE], stock: 19, rating: 4.6, reviews: 88, popularity: 68,
    releasedAt: '2025-09-30',
    description: 'A shirt-jacket in deep corduroy — heavy enough for a layer, soft enough for a shirt.',
    details: ['8-wale corduroy', 'Twin chest pockets', 'Corozo buttons'], tags: ['overshirt', 'cord', 'autumn'],
  }),

  product({
    name: 'Monolith Hoodie', category: 'hoodies', department: 'Unisex', fit: 'oversized',
    fabric: 'fleece', materialLabel: '480gsm brushed loopback', price: 145, compareAt: 175,
    colorways: [INK, BONE, MOSS, CHARTREUSE], stock: 56, rating: 4.9, reviews: 528, popularity: 100,
    releasedAt: '2026-01-28', badge: 'Bestseller', sustainable: true,
    description: 'The heaviest hood we make. Double-layer hood, kangaroo pocket, ribbing that stays put.',
    details: ['480gsm loopback', 'Double-layer hood', 'Kangaroo pocket', 'Rib hem and cuffs'],
    tags: ['heavyweight', 'fleece', 'core', 'winter'],
  }),
  product({
    name: 'Zero Zip Hoodie', category: 'hoodies', department: 'Men', fit: 'regular',
    fabric: 'fleece', materialLabel: '380gsm cotton fleece', price: 132,
    colorways: [GRAPHITE, INDIGO, ASH], stock: 31, rating: 4.6, reviews: 142, popularity: 76,
    releasedAt: '2025-12-08',
    description: 'A clean full-zip with a low-profile hood and set-in sleeves for a sharper line.',
    details: ['Full-length zip', 'Set-in sleeves', 'Side entry pockets'], tags: ['zip', 'layering'],
  }),
  product({
    name: 'Halo Cropped Hoodie', category: 'hoodies', department: 'Women', fit: 'cropped',
    fabric: 'fleece', materialLabel: '340gsm brushed fleece', price: 118,
    colorways: [OAT, EMBER, VOID_], stock: 38, rating: 4.5, reviews: 117, popularity: 70,
    releasedAt: '2026-03-12',
    description: 'A short-body hood with wide ribbing and a relaxed shoulder.',
    details: ['Cropped body', 'Wide rib hem', 'Raw-edge drawcord'], tags: ['cropped', 'soft'],
  }),

  product({
    name: 'Cable Field Knit', category: 'knitwear', department: 'Unisex', fit: 'relaxed',
    fabric: 'wool', materialLabel: 'Lambswool cable knit', price: 198, compareAt: 240,
    colorways: [OAT, MOSS, OXBLOOD, INK], stock: 22, rating: 4.8, reviews: 163, popularity: 84,
    releasedAt: '2025-10-02', sustainable: true,
    description: 'A dense lambswool cable with a high rib collar and saddle shoulders.',
    details: ['Lambswool', 'Saddle shoulder', 'Rib collar, cuffs and hem'],
    care: 'Hand wash cool or wool cycle, reshape and dry flat.',
    tags: ['wool', 'cable', 'winter', 'warm'],
  }),
  product({
    name: 'Merino Base Crew', category: 'knitwear', department: 'Men', fit: 'slim',
    fabric: 'knit', materialLabel: 'Extra-fine merino', price: 156,
    colorways: [GRAPHITE, INDIGO, BONE, SAGE], stock: 44, rating: 4.7, reviews: 219, popularity: 77,
    releasedAt: '2026-02-06', sustainable: true,
    description: 'A fine-gauge merino crew that reads as a shirt layer and a jumper at once.',
    details: ['18.5 micron merino', 'Fully fashioned', 'Flat-lock seams'],
    care: 'Wool cycle, dry flat.', tags: ['merino', 'fine gauge', 'travel'],
  }),
  product({
    name: 'Drift Mohair Sweater', category: 'knitwear', department: 'Women', fit: 'oversized',
    fabric: 'wool', materialLabel: 'Brushed mohair blend', price: 214,
    colorways: [SAND, EMBER, SLATE], stock: 15, rating: 4.6, reviews: 74, popularity: 66,
    releasedAt: '2025-11-19', badge: 'Limited',
    description: 'A haze of brushed mohair with a wide neck and long, falling sleeves.',
    details: ['Brushed mohair blend', 'Wide boat neck', 'Drop shoulder'],
    care: 'Dry clean recommended.', tags: ['mohair', 'fuzzy', 'statement'],
  }),

  product({
    name: 'Orbit Bomber', category: 'jackets', department: 'Unisex', fit: 'relaxed',
    fabric: 'nylon', materialLabel: 'Coated ripstop nylon', price: 288, compareAt: 340,
    colorways: [VOID_, MOSS, SLATE, CHARTREUSE], stock: 17, rating: 4.9, reviews: 198, popularity: 93,
    releasedAt: '2026-01-05', badge: 'Icon',
    description: 'A weightless bomber in coated ripstop with rib collar, cuffs and hem, and a matte two-way zip.',
    details: ['Coated ripstop shell', 'Two-way matte zip', 'Rib collar, cuffs and hem', 'Water repellent'],
    care: 'Wipe clean or cold gentle wash, hang dry.',
    tags: ['bomber', 'technical', 'lightweight', 'icon'],
  }),
  product({
    name: 'Rivet Denim Jacket', category: 'jackets', department: 'Unisex', fit: 'regular',
    fabric: 'denim', materialLabel: '13oz rigid selvedge denim', price: 245,
    colorways: [INDIGO, WASHED, VOID_], stock: 21, rating: 4.7, reviews: 156, popularity: 80,
    releasedAt: '2025-09-12',
    description: 'A rigid selvedge trucker that fades to your shape. Copper hardware, chain-stitch hem.',
    details: ['13oz selvedge', 'Copper rivets', 'Chain-stitch hem'],
    care: 'Wash rarely, cold, inside out.', tags: ['denim', 'selvedge', 'raw', 'fades'],
  }),
  product({
    name: 'Ghost Leather Jacket', category: 'jackets', department: 'Women', fit: 'slim',
    fabric: 'leather', materialLabel: 'Vegetable-tanned lambskin', price: 640,
    colorways: [VOID_, TOBACCO, OXBLOOD], stock: 6, rating: 4.9, reviews: 42, popularity: 71,
    releasedAt: '2026-02-24', badge: 'Atelier',
    description: 'A cropped moto in vegetable-tanned lambskin with an asymmetric zip and hand-set hardware.',
    details: ['Vegetable-tanned lambskin', 'Asymmetric zip', 'Cupro lining'],
    care: 'Leather specialist clean only.', tags: ['leather', 'moto', 'luxury', 'investment'],
  }),
  product({
    name: 'Trail Shell Jacket', category: 'jackets', department: 'Men', fit: 'oversized',
    fabric: 'nylon', materialLabel: '3-layer waterproof shell', price: 395,
    colorways: [MOSS, GRAPHITE, EMBER], stock: 13, rating: 4.8, reviews: 89, popularity: 74,
    releasedAt: '2025-12-01',
    description: 'A taped three-layer shell with pit vents and a helmet-compatible hood.',
    details: ['20k/20k membrane', 'Fully taped seams', 'Pit zips'],
    care: 'Technical wash, tumble low to reactivate DWR.', tags: ['waterproof', 'outdoor', 'shell'],
  }),

  product({
    name: 'Meridian Wool Coat', category: 'coats', department: 'Women', fit: 'oversized',
    fabric: 'wool', materialLabel: 'Double-faced wool cashmere', price: 720, compareAt: 860,
    colorways: [OAT, INK, MOSS], stock: 8, rating: 4.9, reviews: 57, popularity: 82,
    releasedAt: '2025-10-28', badge: 'Atelier',
    description: 'A floor-skimming double-faced coat with a self belt and no lining — every seam is finished by hand.',
    details: ['Double-faced wool cashmere', 'Self belt', 'Hand-finished seams'],
    care: 'Dry clean only.', tags: ['coat', 'wool', 'longline', 'investment'],
  }),
  product({
    name: 'Sentinel Trench', category: 'coats', department: 'Unisex', fit: 'relaxed',
    fabric: 'canvas', materialLabel: 'Waxed cotton canvas', price: 480,
    colorways: [SAND, MOSS, GRAPHITE], stock: 14, rating: 4.7, reviews: 93, popularity: 69,
    releasedAt: '2026-03-08',
    description: 'A waxed cotton trench cut long and easy, with storm flaps and a buckled waist.',
    details: ['Waxed cotton', 'Storm flap', 'Buckled waist belt'],
    care: 'Re-wax annually. Do not machine wash.', tags: ['trench', 'waxed', 'rain'],
  }),

  product({
    name: 'Arc Utility Trouser', category: 'trousers', department: 'Unisex', fit: 'relaxed',
    fabric: 'canvas', materialLabel: 'Ripstop cotton canvas', price: 112, compareAt: 140,
    sizes: 'waist', colorways: [MOSS, INK, SAND], stock: 34, rating: 4.7, reviews: 241, popularity: 87,
    releasedAt: '2026-01-20', badge: 'Bestseller',
    description: 'A wide utility trouser with articulated knees and deep cargo pockets that stay flat.',
    details: ['Articulated knee', 'Bellowed cargo pockets', 'Gusseted crotch'],
    tags: ['cargo', 'utility', 'wide leg'],
  }),
  product({
    name: 'Column Pleat Trouser', category: 'trousers', department: 'Women', fit: 'oversized',
    fabric: 'wool', materialLabel: 'Tropical wool suiting', price: 178,
    sizes: 'waist', colorways: [GRAPHITE, INK, OAT], stock: 26, rating: 4.8, reviews: 132, popularity: 78,
    releasedAt: '2026-02-14',
    description: 'A single-pleat trouser that falls straight from the hip in fluid tropical wool.',
    details: ['Single forward pleat', 'Hook-and-bar closure', 'Unfinished hem for tailoring'],
    care: 'Dry clean.', tags: ['tailoring', 'pleat', 'wide leg', 'office'],
  }),
  product({
    name: 'Trace Track Pant', category: 'trousers', department: 'Men', fit: 'slim',
    fabric: 'fleece', materialLabel: '340gsm loopback cotton', price: 96,
    sizes: 'waist', colorways: [ASH, VOID_, INDIGO], stock: 47, rating: 4.5, reviews: 187, popularity: 72,
    releasedAt: '2025-11-11',
    description: 'A tapered sweatpant with a flat drawcord waist and a clean ankle.',
    details: ['Tapered leg', 'Flat drawcord', 'Zip side pockets'], tags: ['sweatpant', 'lounge', 'tapered'],
  }),

  product({
    name: 'Standard 12 Selvedge Jean', category: 'jeans', department: 'Unisex', fit: 'regular',
    fabric: 'denim', materialLabel: '12.5oz Japanese selvedge', price: 205,
    sizes: 'waist', colorways: [INDIGO, VOID_, WASHED], stock: 29, rating: 4.8, reviews: 276, popularity: 91,
    releasedAt: '2025-08-22', badge: 'Bestseller',
    description: 'A straight-leg selvedge jean cut from Japanese denim that fades hard and honestly.',
    details: ['12.5oz Japanese selvedge', 'Straight leg', 'Copper rivets', 'Chain-stitch hem'],
    care: 'Cold wash inside out, hang dry.', tags: ['selvedge', 'raw denim', 'straight', 'japanese'],
  }),
  product({
    name: 'Wide Bay Jean', category: 'jeans', department: 'Women', fit: 'oversized',
    fabric: 'denim', materialLabel: '11oz washed denim', price: 158,
    sizes: 'waist', colorways: [WASHED, CHALK, VOID_], stock: 36, rating: 4.6, reviews: 164, popularity: 76,
    releasedAt: '2026-03-26',
    description: 'A high-rise wide leg with a soft wash and a long, heavy fall.',
    details: ['High rise', 'Wide straight leg', 'Stone washed'], tags: ['wide leg', 'high rise', 'washed'],
  }),
  product({
    name: 'Taper 08 Stretch Jean', category: 'jeans', department: 'Men', fit: 'slim',
    fabric: 'denim', materialLabel: '10oz comfort stretch denim', price: 128, compareAt: 152,
    sizes: 'waist', colorways: [VOID_, INDIGO, GRAPHITE], stock: 52, rating: 4.4, reviews: 208, popularity: 68,
    releasedAt: '2025-12-16',
    description: 'A tapered stretch jean that moves without losing its line.',
    details: ['2% elastane', 'Tapered leg', 'Reinforced belt loops'], tags: ['stretch', 'tapered', 'everyday'],
  }),

  product({
    name: 'Delta Cargo Short', category: 'shorts', department: 'Unisex', fit: 'relaxed',
    fabric: 'canvas', materialLabel: 'Washed cotton ripstop', price: 82,
    sizes: 'waist', colorways: [SAND, MOSS, INK], stock: 41, rating: 4.5, reviews: 121, popularity: 63,
    releasedAt: '2026-04-10',
    description: 'A mid-length cargo short with a soft washed hand and a stable waistband.',
    details: ['9" inseam', 'Bellowed pockets', 'Washed finish'], tags: ['cargo', 'summer'],
  }),
  product({
    name: 'Lap Running Short', category: 'shorts', department: 'Men', fit: 'slim',
    fabric: 'nylon', materialLabel: 'Featherweight woven nylon', price: 64,
    sizes: 'apparel', colorways: [VOID_, CHARTREUSE, SLATE], stock: 58, rating: 4.6, reviews: 143, popularity: 65,
    releasedAt: '2026-04-18',
    description: 'A 5" running short with a bonded waistband and a zip rear pocket.',
    details: ['5" inseam', 'Bonded waistband', 'Reflective trim'], tags: ['running', 'performance', 'lightweight'],
  }),

  product({
    name: 'Vector Slip Dress', category: 'dresses', department: 'Women', fit: 'slim',
    fabric: 'silk', materialLabel: '22mm charmeuse silk', price: 268, compareAt: 320,
    colorways: [VOID_, OXBLOOD, OAT, SAGE], stock: 16, rating: 4.9, reviews: 118, popularity: 89,
    releasedAt: '2026-02-02', badge: 'Bestseller',
    description: 'A bias-cut charmeuse slip that pours rather than hangs. Adjustable straps, French seams.',
    details: ['Bias cut', 'Adjustable straps', 'French seams'],
    care: 'Cold hand wash or dry clean.', tags: ['slip', 'silk', 'evening', 'bias'],
  }),
  product({
    name: 'Field Midi Dress', category: 'dresses', department: 'Women', fit: 'relaxed',
    fabric: 'cotton', materialLabel: 'Washed cotton poplin', price: 165,
    colorways: [CHALK, SAGE, EMBER], stock: 24, rating: 4.6, reviews: 87, popularity: 70,
    releasedAt: '2026-03-30', sustainable: true,
    description: 'An easy midi with a gathered waist and deep side pockets.',
    details: ['Gathered waist', 'Side seam pockets', 'Organic cotton'], tags: ['midi', 'daywear', 'pockets'],
  }),
  product({
    name: 'Prism Knit Dress', category: 'dresses', department: 'Women', fit: 'slim',
    fabric: 'knit', materialLabel: 'Compact rib knit', price: 195,
    colorways: [INK, CLAY, SLATE], stock: 18, rating: 4.7, reviews: 66, popularity: 64,
    releasedAt: '2025-11-26',
    description: 'A ribbed column dress with enough weight to skim instead of cling.',
    details: ['Compact rib', 'Column silhouette', 'Bonded hem'], tags: ['knit', 'column', 'winter'],
  }),

  product({
    name: 'Pivot Wrap Skirt', category: 'skirts', department: 'Women', fit: 'regular',
    fabric: 'wool', materialLabel: 'Wool flannel', price: 148,
    colorways: [GRAPHITE, OAT, MOSS], stock: 21, rating: 4.6, reviews: 54, popularity: 58,
    releasedAt: '2025-10-20',
    description: 'A wrapped flannel skirt with a hidden closure and a clean front panel.',
    details: ['Wrap front', 'Hidden closure', 'Half lined'],
    care: 'Dry clean.', tags: ['wrap', 'flannel', 'midi'],
  }),
  product({
    name: 'Tier Denim Skirt', category: 'skirts', department: 'Women', fit: 'relaxed',
    fabric: 'denim', materialLabel: '10oz washed denim', price: 118,
    colorways: [WASHED, VOID_, CHALK], stock: 30, rating: 4.4, reviews: 71, popularity: 55,
    releasedAt: '2026-04-06',
    description: 'A tiered denim skirt with a soft wash and a swing that holds its volume.',
    details: ['Two-tier construction', 'Stone washed', 'Back zip'], tags: ['denim', 'tiered', 'volume'],
  }),

  product({
    name: 'Runner 01 Low', category: 'footwear', department: 'Unisex', fit: 'regular',
    fabric: 'suede', materialLabel: 'Suede and mesh upper', price: 185, compareAt: 220,
    sizes: 'shoe', colorways: [BONE, VOID_, MOSS, EMBER], stock: 37, rating: 4.7, reviews: 302, popularity: 95,
    releasedAt: '2026-01-16', badge: 'Bestseller',
    description: 'A low-profile runner on a sculpted foam midsole, with a suede cage over breathable mesh.',
    details: ['Sculpted EVA midsole', 'Suede cage', 'Rubber outsole', 'Recycled laces'],
    care: 'Brush clean, air dry away from heat.', tags: ['sneaker', 'runner', 'low top', 'foam'],
  }),
  product({
    name: 'Court 04 Leather', category: 'footwear', department: 'Unisex', fit: 'regular',
    fabric: 'leather', materialLabel: 'Full-grain leather upper', price: 225,
    sizes: 'shoe', colorways: [CHALK, VOID_, TOBACCO], stock: 23, rating: 4.8, reviews: 176, popularity: 83,
    releasedAt: '2025-09-18',
    description: 'A clean court silhouette in full-grain leather on a cupsole that softens as you wear it.',
    details: ['Full-grain leather', 'Cupsole construction', 'Leather lining'],
    care: 'Condition leather seasonally.', tags: ['sneaker', 'court', 'leather', 'minimal'],
  }),
  product({
    name: 'Trail Grip Mid', category: 'footwear', department: 'Men', fit: 'regular',
    fabric: 'nylon', materialLabel: 'Ripstop and TPU upper', price: 245,
    sizes: 'shoe', colorways: [GRAPHITE, MOSS, CHARTREUSE], stock: 15, rating: 4.6, reviews: 94, popularity: 67,
    releasedAt: '2026-02-28',
    description: 'A mid-cut trail shoe with a lugged outsole and a welded TPU cage.',
    details: ['5mm lugs', 'Welded TPU cage', 'Gusseted tongue'], tags: ['trail', 'grip', 'outdoor', 'mid'],
  }),

  product({
    name: 'Signal 6-Panel Cap', category: 'headwear', department: 'Unisex', fit: 'regular',
    fabric: 'canvas', materialLabel: 'Washed cotton twill', price: 48,
    sizes: 'one', colorways: [INK, BONE, MOSS, CHARTREUSE], stock: 72, rating: 4.6, reviews: 214, popularity: 79,
    releasedAt: '2026-01-08',
    description: 'A soft-crown six-panel with a pre-curved brim and a brass slider.',
    details: ['Unstructured crown', 'Pre-curved brim', 'Brass slider'], tags: ['cap', 'six panel', 'everyday'],
  }),
  product({
    name: 'Ridge Rib Beanie', category: 'headwear', department: 'Unisex', kind: 'beanie', fit: 'regular',
    fabric: 'wool', materialLabel: 'Lambswool rib', price: 55,
    sizes: 'one', colorways: [OXBLOOD, INK, OAT, SLATE], stock: 64, rating: 4.7, reviews: 158, popularity: 73,
    releasedAt: '2025-11-04', sustainable: true,
    description: 'A deep-cuff lambswool beanie with a soft pom you can remove.',
    details: ['Lambswool rib', 'Deep fold cuff', 'Detachable pom'],
    care: 'Hand wash cool, dry flat.', tags: ['beanie', 'wool', 'winter'],
  }),

  product({
    name: 'Cargo Weekend Tote', category: 'bags', department: 'Unisex', fit: 'regular',
    fabric: 'canvas', materialLabel: '18oz waxed canvas', price: 138,
    sizes: 'one', colorways: [SAND, VOID_, MOSS], stock: 28, rating: 4.7, reviews: 132, popularity: 75,
    releasedAt: '2026-02-20', sustainable: true,
    description: 'A structured waxed tote with reinforced webbing handles and an interior sleeve.',
    details: ['18oz waxed canvas', 'Webbing handles', 'Interior laptop sleeve'],
    care: 'Spot clean. Re-wax as needed.', tags: ['tote', 'canvas', 'work', 'travel'],
  }),
  product({
    name: 'Shadow Leather Holdall', category: 'bags', department: 'Unisex', fit: 'regular',
    fabric: 'leather', materialLabel: 'Vegetable-tanned leather', price: 520,
    sizes: 'one', colorways: [TOBACCO, VOID_, OXBLOOD], stock: 7, rating: 4.9, reviews: 38, popularity: 62,
    releasedAt: '2025-12-20', badge: 'Atelier',
    description: 'A hand-finished holdall in vegetable-tanned leather that darkens with use.',
    details: ['Vegetable-tanned leather', 'Solid brass hardware', 'Suede lining'],
    care: 'Condition seasonally.', tags: ['leather', 'holdall', 'travel', 'luxury'],
  }),

  product({
    name: 'Long Wool Scarf', category: 'accessories', department: 'Unisex', fit: 'regular',
    fabric: 'wool', materialLabel: 'Brushed lambswool', price: 88,
    sizes: 'one', colorways: [OAT, OXBLOOD, MOSS, GRAPHITE], stock: 45, rating: 4.7, reviews: 109, popularity: 69,
    releasedAt: '2025-10-08', sustainable: true,
    description: 'A long brushed lambswool scarf with hand-knotted fringe.',
    details: ['Brushed lambswool', '210cm length', 'Hand-knotted fringe'],
    care: 'Dry clean or wool cycle.', tags: ['scarf', 'wool', 'winter', 'gift'],
  }),
  product({
    name: 'Featherweight Silk Scarf', category: 'accessories', department: 'Women', fit: 'regular',
    fabric: 'silk', materialLabel: 'Habotai silk', price: 96,
    sizes: 'one', colorways: [CHALK, EMBER, SAGE], stock: 26, rating: 4.5, reviews: 47, popularity: 52,
    releasedAt: '2026-04-14',
    description: 'A weightless habotai scarf with rolled hand-stitched edges.',
    details: ['Habotai silk', 'Hand-rolled edge', '180cm length'],
    care: 'Dry clean.', tags: ['silk', 'scarf', 'light'],
  }),
]

export const PRICE_BOUNDS = PRODUCTS.reduce(
  (acc, p) => ({ min: Math.min(acc.min, p.price), max: Math.max(acc.max, p.price) }),
  { min: Infinity, max: 0 },
)

export function garmentSpec(product, colorway, angle = -0.42) {
  return {
    kind: product.kind,
    fit: product.fit,
    fabric: product.fabric,
    seed: product.seed,
    color: colorway.hex,
    accent: colorway.accent,
    angle,
  }
}

export const COLLECTIONS = [
  { id: 'new', label: 'New in', test: p => p.releasedAt >= '2026-03-01' },
  { id: 'best', label: 'Bestsellers', test: p => p.popularity >= 85 },
  { id: 'sale', label: 'On sale', test: p => Boolean(p.compareAt) },
  { id: 'sustainable', label: 'Responsible', test: p => p.sustainable },
  { id: 'atelier', label: 'Atelier', test: p => p.price >= 400 },
]
