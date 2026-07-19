So this ecosystem is a set of smart contracts deployed in Polygon mainnet (137) and Amoy testnet (80002). Of course,
users will be able to deploy this as well in their local networks.

The underlying idea is to tie an aesthetic to each address to define some sort of Persona linked to the address.
So a central record will exist to hold each Persona created for an address with something like this:

    // The color for a trait. Only 10 elements.
    enum Color {
	    Black, Blue, DarkBrown, Green, LightBrown, Pink, Purple, Red, White, Yellow
    }

    // A trait is an element to render. It can be a cloth, a body, a hair, ...
    // It should be understood that lotId being 0 means nothing is selected.
    // The first lotId is 1, and will per-deployment (i.e. per-data) stand for
    // REFMAP. Others will / might be added later.
    struct Trait {
        uint128 lotId;
        uint120 itemId;
        Color color;
    }

    // The sex.
    enum Sex { Male, Female }

    // The body color. Male and female have access to images of the same values.
    enum Body { White, Black, Yellow, Orange, Blue, Red, Green, Purple }

    // Whether the character uses simple or standard clothes.
    enum ClothType { Standard, Simple }

    // The different trait types. The body is always resolved from the default
    // lot (which here will be known as lot id 1) in front-end. The `Cloth`
    // category will be, however, unknown / empty to the default lot.
    enum TraitType { Arms, Boots, Chest, Hair, HairTail, Hat, LongShirt, Pants, Shirt, Shoulder, Waist, Cloth, Necklace, Cloak }

    // The rendering of a persona (visual aspects of an account).
    struct Persona {
        string name; // The name will be unique among all the personas.
                     // Even perhaps limiting the ability to change this value?
                     // Even perhaps limiting this field to something like [a-zA-Z0-9_]+
                     // or another sensible approach for names.
        Sex sex;
        Body body;
        ClothType clothType;
        Trait body;
        Trait hair;
        Trait hairTail; // Yes, the hair tail goes separate.
        Trait necklace; // The necklace can come in different tones.
        Trait hat;      // Same for the hat.
        // Left and right hand are not included.
    }

    // The rendering of simple clothes of a persona (when using simple clothes).
    struct SimpleClothing {
        Trait cloth;
    }

    // The rendering of standard clothes of a persona (when using standard clothes).
    struct StandardClothing {
        Trait boots;
        Trait pants;
        Trait shirt;
        Trait chest;
        Trait waist;
        Trait arms;
        Trait longShirt;
        Trait shoulders;
        Trait cloak;
        bool  bootsOverPants;
    }

    // All the registered personas' nicknames. This mapping must key from the
    // normalized (lowercased) name rather than the desired name.
    mapping(string => address) public personasNames;

    // All the registered personas.
    mapping(address => Persona) public personas;

    // For personas with a .Standard clothing, this structure includes the cloth.
    mapping(address => SimpleClothing) public simpleClothing;

    // For personas with a .Standard clothing, this structure includes the cloth.
    mapping(address => StandardClothing) public standardClothing;

Now, this is a sample on how the personas would behave. So far, check whether something is inconsistent
in this structure (the attributes map to something defined in the AlephVault.WindRose.REFMAP add-on), or
whether the types are invalid.

The goal is to store the global aesthetics of a persona (profile for an account) in a specific contract
in the Polygon network.

So in order to tell what can a persona wear or not, first the lots must be defined. They're an array of
things that can only be added (never removed):

    mapping(uint128 lotId => mapping(Sex sex => mapping(TraitType traitType => mapping(uint120 traitId => uint256 colors)))) public availableTraits;

Notice how the lot id, the sex and the trait type are what's used in the AlephVault.WindRose.REFMAP
concept for `resolve(...)`, although proper strings are used there (here, there are some constants that
will be matched to a subset of those allowed strings: `TraitType` enumeration).

Now, defining a lot involves _an administrative role_ first (so there will be a concept of only-owner
or so). Also, defining the lot does not only involve that definition I said over the items but, instead,
also some involved metadata for the lot. This metadata defines:

- The type of location for the lot.
- The contents of that location.

It can be something like this:

    struct TraitsLot {
        string name; // The name of the lot.
        string url;  // The URL of the lot file or resolution mechanism.
    }

    uint128 public nextLotId = 1;

    mapping(uint128 lotId => TraitsLot) public lots;

This lot is modifiable by _an administrative role_ (never removable).

A reason on why _an administrative role_ is required is because we cannot accept any file being used here.
This is related to the licenses over the assets, which is something we cannot assess here. So it is only
an administrative task to perform. This applies to edition and to removal.

Another thing to explain is the URL. The URL is, again, mutable. And it will point to a .zip file. The idea
is that this .zip file will have the following structure:

    /
        Male/
            Arms/
            Boots/
            Chest/
            Cloth/
            Hair/   <--- Also hair tails will resolve here.
            Hat/
            LongShirt/
            Pants/
            Shirt/
            Shoulder/
            Waist/
            Necklace/
            Cloak/
        Female/
            Arms/
            Boots/
            Chest/
            Cloth/
            Hair/   <--- Also hair tails will resolve here.
            Hat/
            LongShirt/
            Pants/
            Shirt/
            Shoulder/
            Waist/
            Necklace/
            Cloak/

where all the directories are optional. This is only considered in front-end (the smart contracts only
include the URL). The URLs can be in many formats:

- http(s)://some.domain/path/to/file.zip
- ipfs://SoMEhASh
- local://somekey (e.g. local://default)

The responsibility for the maintenance and validity of the URLs is the administrative user itself. The
smart contract should never attempt to validate these values, not even in format / syntax of the URLs.
However, an empty name will tell the lot is not registered (so yes: setting the name always reverts if
the name is empty). Registering a new traits lot causes a bump the nextLotId variable by 1.

Also, first, the lot must be registered and THEN the contents of `availableTraits` can be populated.
Doing otherwise will cause a revert. Populating `availableTraits` is also reserved for the same roles
(i.e. administrative roles) that create lots. Each value in the available traits, which is regarded as
`colors`, and it is an integer. This integer is encoded as a binary flag:

`[1bit:Black][1bit:Blue][1bit:DarkBrown][1bit:Green][1bit:LightBrown][1bit:Pink][1bit:Purple][1bit:Red][1bit:White][1bit:Yellow]`

telling all the colors that are available for this object in particular in this lot. For example, the
number 0x000...0003ff (a 256-bit number) means all the 10 colors are selected. All the flags are the least
significant bits (the number 1023, 0x3ff, turns them all).

**Just note**: Resolvers will download the .ZIP files. They will compute a consistent hash and only keep
the file in the case the hash is new (i.e. does not belong to a previously downloaded file).

So each lot is, essentially, an authorization of a Persona to select certain traits. Many lots may have
an intersection of stuff they allow, while referencing the same file.

Now, it happens that a Persona will be allowed by the administrator to one or more lots. This involves:

- On this contract's construction, lot 1 will be registered with:
  - name: "Default"
  - url: "local://default"
  - available traits:
    - `[1][Male][Arms][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Arms][8]` = `0x000...0003ff`
    - `[1][Male][Boots][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Boots][3]` = `0x000...0003ff`
    - `[1][Male][Chest][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Chest][3]` = `0x000...0003ff`
    - `[1][Male][Hair][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Hair][15]` = `0x000...0003ff`
    - `[1][Male][HairTail][7]` = `0x000...0003ff`
    - `[1][Male][Hat][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Hat][7]` = `0x000...0003ff`
    - `[1][Male][LongShirt][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][LongShirt][9]` = `0x000...0003ff`
    - `[1][Male][Pants][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Pants][5]` = `0x000...0003ff`
    - `[1][Male][Shirt][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Shirt][11]` = `0x000...0003ff`
    - `[1][Male][Shoulder][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Shoulder][13]` = `0x000...0003ff`
    - `[1][Male][Waist][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Waist][4]` = `0x000...0003ff`
    - `[1][Female][Arms][1]` = `0x000...0003ff`
    - ...
    - `[1][Female][Arms][7]` = `0x000...0003ff`
    - `[1][Female][Boots][1]` = `0x000...0003ff`
    - `[1][Female][Chest][1]` = `0x000...0003ff`
    - ...
    - `[1][Female][Chest][3]` = `0x000...0003ff`
    - `[1][Female][Hair][1]` = `0x000...0003ff`
    - ...
    - `[1][Female][Hair][15]` = `0x000...0003ff`
    - `[1][Female][HairTail][7]` = `0x000...0003ff`
    - `[1][Female][HairTail][13]` = `0x000...0003ff`
    - `[1][Female][Hat][1]` = `0x000...0003ff`
    - ...
    - `[1][Female][Hat][8]` = `0x000...0003ff`
    - `[1][Female][LongShirt][1]` = `0x000...0003ff`
    - ...
    - `[1][Female][LongShirt][9]` = `0x000...0003ff`
    - `[1][Female][Pants][1]` = `0x000...0003ff`
    - ...
    - `[1][Female][Pants][10]` = `0x000...0003ff`
    - `[1][Female][Shirt][1]` = `0x000...0003ff`
    - ...
    - `[1][Female][Shirt][17]` = `0x000...0003ff`
    - `[1][Female][Shoulder][1]` = `0x000...0003ff`
    - ...
    - `[1][Female][Shoulder][7]` = `0x000...0003ff`
    - `[1][Male][Waist][1]` = `0x000...0003ff`
    - ...
    - `[1][Male][Waist][2]` = `0x000...0003ff`
- On persona creation, the lot 1 will be allowed by default.

Now, when doing the setup of lot 1, and this applies for any lot traits entry, trigger an event like this:
`(lotId indexed, sex, traitType, traitIndex, colorsBeingAdded)`. Also, in that step, colors must be MERGED, not
replace the previous entries. The merge logic is done via a simple bitwise `or` operator. So the very creation
or deployment of the contract will trigger a lot of events.

Instead, if this consumes a lot of deployment bytecode, lets the installation of lot 1 be done by receiving the
data at construction time, as an array of tuples `(sex, traitType, traitIndex, colorsBeingAdded)`. The logic would
be the same, however.

Now, the logic to create or update a persona is entirely user-triggered and will look like the following blocks.
Please take all the provisions to avoid `Stack too Deep` errors:

    function register(Persona memory persona, SimpleClothing[] memory simpleClothing, StandardClothing[] memory standardClothing) public { /* stuff here */ }

Where each array must be of length 0 or 1 depending on whether the persona uses type Simple or Standard for clothing.

ALL THE DATA MUST BE VALIDATED FOR THE NAME, BODY, AND SELECTED TRAITS.

- The sender must not have a valid persona so far.
- The name must not already be present in the mapping {name} => {persona}. It must NOT be empty.
- The body color, sex, and clothing type must be valid.
- According to the clothing type, 
- All the base traits must be valid (either in lot 0 or in the set of default allowed lots - this will be defined later).
- According to the chosen clothing type, the corresponding argument must have a length of 1 and the other one a length of 0.
  - Also, all the traits defined in the struct at the [0] index must be valid (either in lot 0 or allowed in those lots
    allowed by default).
- If you feel I'm losing anything here on validation, tell me.

Now, there's another similar method to define:

    function registerFor(address target, Persona memory persona, SimpleClothing[] memory simpleClothing, StandardClothing[] memory standardClothing, uint256 validSince, uint256 validUntil) { ... }

The logic is similar, but using a delegated EIP-712 signed from the `target` address. The logic is as if the target
address required registering a persona. The EIP-712 must refer to all those arguments, save the `target` itself which,
instead, should be matched against the result of the signature's signer. A difference will be that the check for allowed
trait lots would not involve the default but all the allowed lots for that persona instead (including the default ones).

We can be defensive here and anticipate for post-quantum signatures, so you can:

1. Add another argument, e.g. of bytes type, to specify stuff like a public key and signing methods.
2. Add another argument to tell the signing type to execute a proper verification.
3. EIP-712 via ecrecover would be the 1st thing available.

HERE YOU APPLY THE BEST PRACTICES YOU CAN TELL ABOUT IN TERMS OF BEING DEFENSIVE. Do not invent them on the fly as your
first attempt, but research first.

Then, after these methods are set, two similar methods to UPDATE A PERSONA are needed. The difference is that:

- No restrictions on update.
- The name will be ignored on update. We might define a separate method for this.

Since there's however a lot of common logic, decouple the common logic into separate private methods.

The methods might be called `update` and `updateFor`.

Other methods I might need are admin methods to:

- Register a new lot.
- Modify a lot's name / caption or URL.
- Register a new lot trait / colors, for an existing lot.
- Register new signature methods? I'm not sure about this.
- Annotate an existing lot as a default lot (all the personas would be allowed to it).
- Annotate an existing lot as allowed to an existing persona. The persona checks on
  valid lots will always involve default lots + custom allowed lots.

And perhaps other methods:

- Check if a persona exists? (perhaps not - perhaps the emptiness of the name in the mapping is enough).
- Get all the nickname changes of an address? (if we allow nickname changes).
- Check if a lot is allowed for a persona.
Not sure which other methods are sensible here.

Please if the contract grows a lot, beyond its limit, you might want to split the functionality in several contracts.

But tell me if something is missing here.