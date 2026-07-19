// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Semperland persona registry.
/// @notice Stores one visual identity per address, with admin-controlled trait lots.
/// @dev This contract intentionally stores only identity/aesthetic metadata. Asset URL contents,
///      URL syntax, ZIP validity, and renderer compatibility are enforced off-chain by clients.
contract SemperlandPersona is Ownable {
    enum Color {
        Black,
        Blue,
        DarkBrown,
        Green,
        LightBrown,
        Pink,
        Purple,
        Red,
        White,
        Yellow
    }

    enum Sex {
        Male,
        Female
    }

    enum Body {
        White,
        Black,
        Yellow,
        Orange,
        Blue,
        Red,
        Green,
        Purple
    }

    enum ClothType {
        Standard,
        Simple
    }

    enum TraitType {
        Arms,
        Boots,
        Chest,
        Hair,
        HairTail,
        Hat,
        LongShirt,
        Pants,
        Shirt,
        Shoulder,
        Waist,
        Cloth,
        Necklace,
        Cloak
    }

    struct Trait {
        /// @dev `0` means no object is selected. If non-zero, `itemId` must be non-zero and authorized.
        uint128 lotId;
        uint120 itemId;
        Color color;
    }

    /// @notice Base persona record. The name is normalized to lowercase before storage.
    /// @dev Body is an enum value, not a trait lot entry. Optional traits use `Trait.lotId == 0`.
    struct Persona {
        string name;
        Sex sex;
        Body body;
        ClothType clothType;
        Trait hair;
        Trait hairTail;
        Trait necklace;
        Trait hat;
    }

    /// @notice Simple clothing mode payload. Required exactly once when `Persona.clothType == Simple`.
    struct SimpleClothing {
        Trait cloth;
    }

    /// @notice Standard clothing mode payload. Required exactly once when `Persona.clothType == Standard`.
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
        bool bootsOverPants;
    }

    /// @notice Metadata for a trait lot.
    /// @dev An empty `name` denotes an unregistered lot. The `url` is opaque and never syntax-checked.
    struct TraitsLot {
        string name;
        string url;
    }

    /// @notice Constructor/admin input for trait availability.
    /// @dev `colors` is a bitset over the 10 `Color` enum values and must fit in `ALL_COLORS`.
    struct TraitAvailability {
        Sex sex;
        TraitType traitType;
        uint120 traitId;
        uint256 colors;
    }

    /// @dev Compact internal form used when hashing delegated EIP-712 requests.
    struct Delegation {
        uint256 validSince;
        uint256 validUntil;
        uint256 nonce;
        uint8 signatureScheme;
        bytes32 authDataHash;
    }

    /// @notice Signature envelope for delegated `*For` methods.
    /// @dev `signatureScheme == SIGNATURE_SCHEME_ECDSA` is the only implemented scheme today.
    ///      `authData` is hashed into the signed payload so later schemes can bind extra public
    ///      keys, algorithm identifiers, or verifier metadata without changing the method ABI.
    struct SignatureAuthorization {
        uint256 validSince;
        uint256 validUntil;
        uint8 signatureScheme;
        bytes authData;
        bytes signature;
    }

    uint8 public constant SIGNATURE_SCHEME_ECDSA = 1;
    uint128 public constant DEFAULT_LOT_ID = 1;
    uint256 public constant ALL_COLORS = (1 << 10) - 1;

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant EIP712_NAME_HASH = keccak256("SemperlandPersona");
    bytes32 private constant EIP712_VERSION_HASH = keccak256("1");
    bytes32 private constant TRAIT_TYPEHASH =
        keccak256("Trait(uint128 lotId,uint120 itemId,uint8 color)");
    bytes32 private constant PERSONA_TYPEHASH =
        keccak256(
            "Persona(string name,uint8 sex,uint8 body,uint8 clothType,bytes32 hair,bytes32 hairTail,bytes32 necklace,bytes32 hat)"
        );
    bytes32 private constant SIMPLE_CLOTHING_TYPEHASH = keccak256("SimpleClothing(bytes32 cloth)");
    bytes32 private constant STANDARD_CLOTHING_TYPEHASH =
        keccak256(
            "StandardClothing(bytes32 boots,bytes32 pants,bytes32 shirt,bytes32 chest,bytes32 waist,bytes32 arms,bytes32 longShirt,bytes32 shoulders,bytes32 cloak,bool bootsOverPants)"
        );
    bytes32 private constant REGISTER_TYPEHASH =
        keccak256(
            "RegisterFor(address target,bytes32 personaHash,bytes32 simpleHash,bytes32 standardHash,uint256 validSince,uint256 validUntil,uint256 nonce,uint8 signatureScheme,bytes32 authDataHash)"
        );
    bytes32 private constant UPDATE_TYPEHASH =
        keccak256(
            "UpdateFor(address target,bytes32 personaHash,bytes32 simpleHash,bytes32 standardHash,uint256 validSince,uint256 validUntil,uint256 nonce,uint8 signatureScheme,bytes32 authDataHash)"
        );
    bytes32 private constant CHANGE_NAME_TYPEHASH =
        keccak256(
            "ChangeNameFor(address target,bytes32 nameHash,uint256 validSince,uint256 validUntil,uint256 nonce,uint8 signatureScheme,bytes32 authDataHash)"
        );

    uint128 public nextLotId;

    /// @notice Maps normalized persona names to their owning account.
    mapping(string normalizedName => address owner) public personasNames;
    /// @notice Maps an account to its current persona. Empty `name` means no registered persona.
    mapping(address account => Persona persona) public personas;
    /// @notice Simple clothing payloads for accounts currently using simple clothing.
    mapping(address account => SimpleClothing simpleClothing) public simpleClothing;
    /// @notice Standard clothing payloads for accounts currently using standard clothing.
    mapping(address account => StandardClothing standardClothing) public standardClothing;
    /// @notice Registered trait lots. Lot ids are append-only and never removed.
    mapping(uint128 lotId => TraitsLot lot) public lots;
    /// @notice Authorized trait/color bitsets by lot, sex, trait type, and trait id.
    mapping(uint128 lotId => mapping(Sex sex => mapping(TraitType traitType => mapping(uint120 traitId => uint256 colors))))
        public availableTraits;
    /// @notice Lots allowed to every persona by default.
    mapping(uint128 lotId => bool isDefault) public defaultLots;
    /// @notice Additional lots allowed to a specific account.
    mapping(address account => mapping(uint128 lotId => bool isAllowed)) public allowedLots;
    /// @notice Replay-protection nonce for each account's delegated actions.
    mapping(address account => uint256 nonce) public nonces;

    bytes32 private immutable _domainSeparator;
    uint256 private immutable _domainChainId;

    error InvalidName();
    error PersonaAlreadyRegistered(address account);
    error PersonaNotRegistered(address account);
    error NameAlreadyRegistered(string normalizedName, address currentOwner);
    error InvalidClothingArguments();
    error InvalidLot(uint128 lotId);
    error InvalidColors(uint256 colors);
    error InvalidTrait(TraitType traitType, uint128 lotId, uint120 itemId, Color color);
    error InvalidValidityWindow();
    error UnsupportedSignatureScheme(uint8 signatureScheme);
    error InvalidSignature();

    event TraitsLotRegistered(uint128 indexed lotId, string name, string url);
    event TraitsLotUpdated(uint128 indexed lotId, string name, string url);
    event TraitColorsAdded(
        uint128 indexed lotId,
        Sex sex,
        TraitType traitType,
        uint120 traitId,
        uint256 colorsBeingAdded,
        uint256 colorsAfter
    );
    event DefaultLotSet(uint128 indexed lotId, bool allowed);
    event PersonaLotSet(address indexed account, uint128 indexed lotId, bool allowed);
    event PersonaRegistered(address indexed account, string normalizedName);
    event PersonaUpdated(address indexed account);
    event PersonaNameChanged(address indexed account, string oldNormalizedName, string newNormalizedName);

    /// @notice Deploys the registry, registers lot 1 as `Default`, and seeds its trait table.
    /// @dev The constructor takes the default trait table to avoid bloating deployment bytecode.
    ///      The deployer becomes the owner and can later manage lots and trait availability.
    /// @param defaultTraits Trait/color entries to OR into default lot 1.
    constructor(TraitAvailability[] memory defaultTraits)
        Ownable(msg.sender)
    {
        _domainChainId = block.chainid;
        _domainSeparator = _buildDomainSeparator();
        nextLotId = DEFAULT_LOT_ID;
        _registerTraitsLot("Default", "local://default");
        defaultLots[DEFAULT_LOT_ID] = true;
        emit DefaultLotSet(DEFAULT_LOT_ID, true);

        for (uint256 i = 0; i < defaultTraits.length; i++) {
            TraitAvailability memory item = defaultTraits[i];
            _addAvailableTraitColors(DEFAULT_LOT_ID, item.sex, item.traitType, item.traitId, item.colors);
        }
    }

    /// @notice Registers the caller's persona.
    /// @dev Reverts if the caller already has a persona, if the normalized name is already taken,
    ///      if the name format is invalid, if the clothing payload does not match `clothType`,
    ///      or if any non-empty trait is not authorized by a default or caller-allowed lot.
    /// @param persona Persona data to store. `persona.name` is normalized before storage.
    /// @param simpleClothing_ Must contain exactly one item for simple clothing, otherwise empty.
    /// @param standardClothing_ Must contain exactly one item for standard clothing, otherwise empty.
    function register(
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) external {
        _registerFor(msg.sender, persona, simpleClothing_, standardClothing_);
    }

    /// @notice Registers a persona for `target` using a signed authorization from `target`.
    /// @dev Anyone may submit the transaction. The target signs the normalized persona/name,
    ///      clothing hashes, validity window, current nonce, signature scheme, and auth-data hash.
    ///      A successful call increments `nonces[target]`, making the signature single-use.
    /// @param target Account receiving the persona.
    /// @param persona Persona data to store for `target`.
    /// @param simpleClothing_ Simple clothing payload, constrained by `persona.clothType`.
    /// @param standardClothing_ Standard clothing payload, constrained by `persona.clothType`.
    /// @param authorization Signature envelope and validity window.
    function registerFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_,
        SignatureAuthorization calldata authorization
    ) external {
        bytes32 structHash =
            _hashRegisterFor(target, persona, simpleClothing_, standardClothing_, authorization);
        _verifyAuthorization(target, structHash, authorization);
        _registerFor(target, persona, simpleClothing_, standardClothing_);
    }

    /// @notice Updates the caller's persona traits, body, sex, and clothing mode.
    /// @dev The stored name is preserved; use `changeName` to update it. The caller must already
    ///      have a persona, and all trait/clothing validation rules are re-applied.
    /// @param persona New persona data. `persona.name` is ignored.
    /// @param simpleClothing_ Must contain exactly one item for simple clothing, otherwise empty.
    /// @param standardClothing_ Must contain exactly one item for standard clothing, otherwise empty.
    function update(
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) external {
        _updateFor(msg.sender, persona, simpleClothing_, standardClothing_);
    }

    /// @notice Updates a persona for `target` using a signed authorization from `target`.
    /// @dev Anyone may submit the transaction. The target signs the persona without the name,
    ///      clothing hashes, validity window, current nonce, signature scheme, and auth-data hash.
    ///      A successful call increments `nonces[target]`, making the signature single-use.
    /// @param target Account whose persona is updated.
    /// @param persona New persona data. `persona.name` is ignored.
    /// @param simpleClothing_ Simple clothing payload, constrained by `persona.clothType`.
    /// @param standardClothing_ Standard clothing payload, constrained by `persona.clothType`.
    /// @param authorization Signature envelope and validity window.
    function updateFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_,
        SignatureAuthorization calldata authorization
    ) external {
        bytes32 structHash =
            _hashUpdateFor(target, persona, simpleClothing_, standardClothing_, authorization);
        _verifyAuthorization(target, structHash, authorization);
        _updateFor(target, persona, simpleClothing_, standardClothing_);
    }

    /// @notice Changes the caller's persona name.
    /// @dev The caller must already have a persona. The new normalized name must be valid and
    ///      unused, unless it is already owned by the caller.
    /// @param newName New desired name. It is normalized to lowercase before storage.
    function changeName(string memory newName) external {
        _changeNameFor(msg.sender, newName);
    }

    /// @notice Changes `target`'s persona name using a signed authorization from `target`.
    /// @dev Anyone may submit the transaction. The target signs the normalized new name,
    ///      validity window, current nonce, signature scheme, and auth-data hash.
    ///      A successful call increments `nonces[target]`.
    /// @param target Account whose persona name is changed.
    /// @param newName New desired name. It is normalized to lowercase before hashing/storage.
    /// @param authorization Signature envelope and validity window.
    function changeNameFor(
        address target,
        string memory newName,
        SignatureAuthorization calldata authorization
    ) external {
        string memory normalizedName = _normalizeName(newName);
        bytes32 structHash = _hashChangeNameFor(target, normalizedName, authorization);
        _verifyAuthorization(target, structHash, authorization);
        _changeNameFor(target, newName);
    }

    /// @notice Registers a new trait lot.
    /// @dev Owner-only. Lots are append-only: the new lot id is `nextLotId`, then `nextLotId`
    ///      is incremented. `name` must be non-empty; `url` is intentionally opaque.
    /// @param name Human-readable lot name. Empty names are invalid because emptiness marks absence.
    /// @param url Opaque resolver URL, e.g. http(s), ipfs, or local.
    /// @return lotId The id assigned to the newly registered lot.
    function registerTraitsLot(string memory name, string memory url) external onlyOwner returns (uint128 lotId) {
        lotId = _registerTraitsLot(name, url);
    }

    /// @notice Updates metadata for an existing trait lot.
    /// @dev Owner-only. This does not change trait availability, default-lot status, or per-account grants.
    ///      `name` must be non-empty; `url` is intentionally opaque.
    /// @param lotId Existing lot id.
    /// @param name New non-empty lot name.
    /// @param url New opaque resolver URL.
    function updateTraitsLot(uint128 lotId, string memory name, string memory url) external onlyOwner {
        _requireRegisteredLot(lotId);
        if (bytes(name).length == 0) revert InvalidName();
        lots[lotId] = TraitsLot({name: name, url: url});
        emit TraitsLotUpdated(lotId, name, url);
    }

    /// @notice Adds allowed colors for a trait in an existing lot.
    /// @dev Owner-only. Colors are merged with bitwise OR and never cleared by this method.
    ///      `traitId` must be non-zero because item ids start at 1. `colors` must be a non-empty
    ///      subset of `ALL_COLORS`.
    /// @param lotId Existing lot id.
    /// @param sex Sex dimension used by the renderer.
    /// @param traitType Trait category.
    /// @param traitId Trait item id inside the lot/category. Must be non-zero.
    /// @param colors Bitset of colors being added.
    function addAvailableTraitColors(
        uint128 lotId,
        Sex sex,
        TraitType traitType,
        uint120 traitId,
        uint256 colors
    ) external onlyOwner {
        _addAvailableTraitColors(lotId, sex, traitType, traitId, colors);
    }

    /// @notice Sets whether a registered lot is available to every persona.
    /// @dev Owner-only. The lot must already be registered. Disabling a default lot does not
    ///      rewrite existing personas, but future registrations/updates will validate against
    ///      the current default/per-account lot configuration.
    /// @param lotId Existing lot id.
    /// @param allowed Whether the lot is globally allowed.
    function setDefaultLot(uint128 lotId, bool allowed) external onlyOwner {
        _requireRegisteredLot(lotId);
        defaultLots[lotId] = allowed;
        emit DefaultLotSet(lotId, allowed);
    }

    /// @notice Sets whether a registered lot is available to one account.
    /// @dev Owner-only. This grant is additive with `defaultLots`.
    /// @param account Account receiving or losing the lot grant.
    /// @param lotId Existing lot id.
    /// @param allowed Whether the lot is allowed for `account`.
    function setAllowedLot(address account, uint128 lotId, bool allowed) external onlyOwner {
        _requireRegisteredLot(lotId);
        allowedLots[account][lotId] = allowed;
        emit PersonaLotSet(account, lotId, allowed);
    }

    /// @notice Returns whether an account has a registered persona.
    /// @dev Presence is represented by a non-empty stored persona name.
    /// @param account Account to check.
    function personaExists(address account) public view returns (bool) {
        return bytes(personas[account].name).length != 0;
    }

    /// @notice Returns whether `lotId` is available to `account`.
    /// @dev A lot is allowed if it is default or explicitly granted to the account.
    /// @param account Account whose grants are checked.
    /// @param lotId Lot id to check.
    function isLotAllowed(address account, uint128 lotId) public view returns (bool) {
        return defaultLots[lotId] || allowedLots[account][lotId];
    }

    /// @notice Normalizes and validates a persona name without storing it.
    /// @dev Valid names are 3 to 32 ASCII bytes, start with `[a-zA-Z_]`, and continue
    ///      with `[a-zA-Z0-9_]`. Returned names are lowercase.
    /// @param name Name to normalize.
    function normalizeName(string memory name) external pure returns (string memory) {
        return _normalizeName(name);
    }

    /// @notice Returns the EIP-712 domain separator used by delegated methods.
    /// @dev Recomputed if the chain id changes after deployment.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _registerFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) private {
        // Registration is one-time per account. The name reservation is written only after
        // all persona and clothing validation succeeds.
        if (personaExists(target)) revert PersonaAlreadyRegistered(target);

        string memory normalizedName = _normalizeName(persona.name);
        address currentOwner = personasNames[normalizedName];
        if (currentOwner != address(0)) revert NameAlreadyRegistered(normalizedName, currentOwner);

        persona.name = normalizedName;
        _storePersona(target, persona, simpleClothing_, standardClothing_);
        personasNames[normalizedName] = target;

        emit PersonaRegistered(target, normalizedName);
    }

    function _updateFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) private {
        // Updates deliberately preserve the name. This prevents callers from accidentally
        // bypassing the explicit name-change flow and its clearer UX/security expectations.
        if (!personaExists(target)) revert PersonaNotRegistered(target);

        persona.name = personas[target].name;
        _storePersona(target, persona, simpleClothing_, standardClothing_);

        emit PersonaUpdated(target);
    }

    function _changeNameFor(address target, string memory newName) private {
        // Name ownership is keyed by normalized lowercase names. Reusing the same name with
        // different casing is allowed only for the account that already owns it.
        if (!personaExists(target)) revert PersonaNotRegistered(target);

        string memory oldNormalizedName = personas[target].name;
        string memory newNormalizedName = _normalizeName(newName);
        address currentOwner = personasNames[newNormalizedName];
        if (currentOwner != address(0) && currentOwner != target) {
            revert NameAlreadyRegistered(newNormalizedName, currentOwner);
        }

        delete personasNames[oldNormalizedName];
        personasNames[newNormalizedName] = target;
        personas[target].name = newNormalizedName;

        emit PersonaNameChanged(target, oldNormalizedName, newNormalizedName);
    }

    function _storePersona(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_
    ) private {
        // The selected clothing mode determines which auxiliary mapping is active.
        // The inactive mapping is cleared so off-chain readers do not see stale clothing.
        _validatePersonaTraits(target, persona.sex, persona);

        if (persona.clothType == ClothType.Simple) {
            if (simpleClothing_.length != 1 || standardClothing_.length != 0) revert InvalidClothingArguments();
            _validateTrait(target, persona.sex, TraitType.Cloth, simpleClothing_[0].cloth);
            simpleClothing[target] = simpleClothing_[0];
            delete standardClothing[target];
        } else {
            if (simpleClothing_.length != 0 || standardClothing_.length != 1) revert InvalidClothingArguments();
            _validateStandardClothing(target, persona.sex, standardClothing_[0]);
            standardClothing[target] = standardClothing_[0];
            delete simpleClothing[target];
        }

        personas[target] = persona;
    }

    function _validatePersonaTraits(address target, Sex sex, Persona memory persona) private view {
        // Body is validated by Solidity enum decoding. Wearable base traits are validated
        // against available lot entries unless they are empty (`lotId == 0`).
        _validateTrait(target, sex, TraitType.Hair, persona.hair);
        _validateTrait(target, sex, TraitType.HairTail, persona.hairTail);
        _validateTrait(target, sex, TraitType.Necklace, persona.necklace);
        _validateTrait(target, sex, TraitType.Hat, persona.hat);
    }

    function _validateStandardClothing(address target, Sex sex, StandardClothing memory clothing) private view {
        // Standard clothing has independent trait slots; each one may be empty or must
        // resolve to a currently authorized lot/item/color combination.
        _validateTrait(target, sex, TraitType.Boots, clothing.boots);
        _validateTrait(target, sex, TraitType.Pants, clothing.pants);
        _validateTrait(target, sex, TraitType.Shirt, clothing.shirt);
        _validateTrait(target, sex, TraitType.Chest, clothing.chest);
        _validateTrait(target, sex, TraitType.Waist, clothing.waist);
        _validateTrait(target, sex, TraitType.Arms, clothing.arms);
        _validateTrait(target, sex, TraitType.LongShirt, clothing.longShirt);
        _validateTrait(target, sex, TraitType.Shoulder, clothing.shoulders);
        _validateTrait(target, sex, TraitType.Cloak, clothing.cloak);
    }

    function _validateTrait(address target, Sex sex, TraitType traitType, Trait memory trait) private view {
        // Lot 0 is the sentinel for "not worn". In that case item id and color are ignored.
        if (trait.lotId == 0) return;

        // Non-empty traits must refer to an item id starting at 1 and a lot that is
        // currently available either globally or to this specific account.
        if (trait.itemId == 0 || !isLotAllowed(target, trait.lotId)) {
            revert InvalidTrait(traitType, trait.lotId, trait.itemId, trait.color);
        }

        // Color availability is encoded in the low ten bits of the lot entry.
        uint256 colors = availableTraits[trait.lotId][sex][traitType][trait.itemId];
        if ((colors & (1 << uint8(trait.color))) == 0) {
            revert InvalidTrait(traitType, trait.lotId, trait.itemId, trait.color);
        }
    }

    function _registerTraitsLot(string memory name, string memory url) private returns (uint128 lotId) {
        // Empty names are forbidden because `bytes(lots[id].name).length == 0` is the
        // contract-wide test for an unregistered lot.
        if (bytes(name).length == 0) revert InvalidName();

        lotId = nextLotId;
        lots[lotId] = TraitsLot({name: name, url: url});
        nextLotId = lotId + 1;

        emit TraitsLotRegistered(lotId, name, url);
    }

    function _addAvailableTraitColors(
        uint128 lotId,
        Sex sex,
        TraitType traitType,
        uint120 traitId,
        uint256 colors
    ) private {
        // Trait availability is monotonic: new color flags are OR-merged into the
        // existing bitset. Removal is intentionally absent from this simple registry.
        _requireRegisteredLot(lotId);
        if (traitId == 0) revert InvalidTrait(traitType, lotId, traitId, Color.Black);
        if (colors == 0 || (colors & ~ALL_COLORS) != 0) revert InvalidColors(colors);

        uint256 colorsAfter = availableTraits[lotId][sex][traitType][traitId] | colors;
        availableTraits[lotId][sex][traitType][traitId] = colorsAfter;

        emit TraitColorsAdded(lotId, sex, traitType, traitId, colors, colorsAfter);
    }

    function _requireRegisteredLot(uint128 lotId) private view {
        // The lot id space is append-only, so a non-empty name is enough to identify
        // ids that were actually registered.
        if (bytes(lots[lotId].name).length == 0) revert InvalidLot(lotId);
    }

    function _verifyAuthorization(
        address target,
        bytes32 structHash,
        SignatureAuthorization calldata authorization
    ) private {
        // Delegated calls are valid only inside the signed time window. This keeps
        // leaked or forgotten signatures from remaining usable forever.
        if (
            authorization.validSince > authorization.validUntil ||
            block.timestamp < authorization.validSince ||
            block.timestamp > authorization.validUntil
        ) {
            revert InvalidValidityWindow();
        }
        if (authorization.signatureScheme != SIGNATURE_SCHEME_ECDSA) {
            revert UnsupportedSignatureScheme(authorization.signatureScheme);
        }

        // The recovered ECDSA signer must be the target account. The nonce is consumed
        // only after successful recovery, so failed attempts do not invalidate a signature.
        address signer = ECDSA.recover(_hashTypedDataV4(structHash), authorization.signature);
        if (signer != target) revert InvalidSignature();

        nonces[target]++;
    }

    function _hashRegisterFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_,
        SignatureAuthorization calldata authorization
    ) private view returns (bytes32) {
        // Registration signs the normalized name as part of the persona hash because
        // choosing a name creates a unique global reservation.
        return _hashDelegatedClothingAction(
            REGISTER_TYPEHASH,
            target,
            _hashPersona(persona, true),
            _hashSimpleClothingArray(simpleClothing_),
            _hashStandardClothingArray(standardClothing_),
            _delegation(target, authorization)
        );
    }

    function _hashUpdateFor(
        address target,
        Persona memory persona,
        SimpleClothing[] memory simpleClothing_,
        StandardClothing[] memory standardClothing_,
        SignatureAuthorization calldata authorization
    ) private view returns (bytes32) {
        // Updates exclude the name from the persona hash because the update flow
        // preserves names by design.
        return _hashDelegatedClothingAction(
            UPDATE_TYPEHASH,
            target,
            _hashPersona(persona, false),
            _hashSimpleClothingArray(simpleClothing_),
            _hashStandardClothingArray(standardClothing_),
            _delegation(target, authorization)
        );
    }

    function _hashChangeNameFor(
        address target,
        string memory normalizedName,
        SignatureAuthorization calldata authorization
    ) private view returns (bytes32) {
        // Name changes sign only the normalized name, keeping the action small and
        // distinct from broader persona/clothing updates.
        Delegation memory delegation_ = _delegation(target, authorization);
        return keccak256(
            abi.encode(
                CHANGE_NAME_TYPEHASH,
                target,
                keccak256(bytes(normalizedName)),
                delegation_.validSince,
                delegation_.validUntil,
                delegation_.nonce,
                delegation_.signatureScheme,
                delegation_.authDataHash
            )
        );
    }

    function _delegation(
        address target,
        SignatureAuthorization calldata authorization
    ) private view returns (Delegation memory) {
        // Snapshot the current nonce and auth-data hash into a compact struct so every
        // delegated action uses the same replay/future-scheme fields.
        return Delegation({
            validSince: authorization.validSince,
            validUntil: authorization.validUntil,
            nonce: nonces[target],
            signatureScheme: authorization.signatureScheme,
            authDataHash: keccak256(authorization.authData)
        });
    }

    function _hashDelegatedClothingAction(
        bytes32 typeHash,
        address target,
        bytes32 personaHash,
        bytes32 simpleHash,
        bytes32 standardHash,
        Delegation memory delegation_
    ) private pure returns (bytes32) {
        // Register/update share the same payload layout and differ only by type hash.
        return keccak256(
            abi.encode(
                typeHash,
                target,
                personaHash,
                simpleHash,
                standardHash,
                delegation_.validSince,
                delegation_.validUntil,
                delegation_.nonce,
                delegation_.signatureScheme,
                delegation_.authDataHash
            )
        );
    }

    function _hashTypedDataV4(bytes32 structHash) private view returns (bytes32) {
        // Minimal EIP-712 v4 final digest. Implemented locally to keep the contract
        // compatible with the project's current Paris EVM target.
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    function _domainSeparatorV4() private view returns (bytes32) {
        // If the chain id changes after deployment, recompute to preserve replay protection
        // across forks.
        if (block.chainid == _domainChainId) return _domainSeparator;
        return _buildDomainSeparator();
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, EIP712_NAME_HASH, EIP712_VERSION_HASH, block.chainid, address(this))
        );
    }

    function _normalizeName(string memory name) private pure returns (string memory) {
        // Names are ASCII-only by construction because the validation works byte-by-byte.
        // Length is bytes, not Unicode code points.
        bytes memory raw = bytes(name);
        uint256 length = raw.length;
        if (length < 3 || length > 32) revert InvalidName();
        if (!_isNameStart(raw[0])) revert InvalidName();

        bytes memory normalized = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = raw[i];
            if (i == 0) {
                if (!_isNameStart(char)) revert InvalidName();
            } else if (!_isNamePart(char)) {
                revert InvalidName();
            }

            normalized[i] = _toLower(char);
        }

        return string(normalized);
    }

    function _isNameStart(bytes1 char) private pure returns (bool) {
        return char == 0x5f || (char >= 0x41 && char <= 0x5a) || (char >= 0x61 && char <= 0x7a);
    }

    function _isNamePart(bytes1 char) private pure returns (bool) {
        return _isNameStart(char) || (char >= 0x30 && char <= 0x39);
    }

    function _toLower(bytes1 char) private pure returns (bytes1) {
        if (char >= 0x41 && char <= 0x5a) {
            return bytes1(uint8(char) + 32);
        }
        return char;
    }

    function _hashTrait(Trait memory trait) private pure returns (bytes32) {
        return keccak256(abi.encode(TRAIT_TYPEHASH, trait.lotId, trait.itemId, uint8(trait.color)));
    }

    function _hashPersona(Persona memory persona, bool includeName) private pure returns (bytes32) {
        // `includeName` is true for registration and false for update, matching the
        // external method semantics.
        return keccak256(
            abi.encode(
                PERSONA_TYPEHASH,
                includeName ? keccak256(bytes(_normalizeName(persona.name))) : keccak256(bytes("")),
                uint8(persona.sex),
                uint8(persona.body),
                uint8(persona.clothType),
                _hashTrait(persona.hair),
                _hashTrait(persona.hairTail),
                _hashTrait(persona.necklace),
                _hashTrait(persona.hat)
            )
        );
    }

    function _hashSimpleClothingArray(SimpleClothing[] memory clothing) private pure returns (bytes32) {
        // Arrays are represented as the keccak of concatenated element struct hashes,
        // mirroring EIP-712 array hashing.
        bytes32[] memory hashes = new bytes32[](clothing.length);
        for (uint256 i = 0; i < clothing.length; i++) {
            hashes[i] = keccak256(abi.encode(SIMPLE_CLOTHING_TYPEHASH, _hashTrait(clothing[i].cloth)));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _hashStandardClothingArray(StandardClothing[] memory clothing) private pure returns (bytes32) {
        // Arrays are represented as the keccak of concatenated element struct hashes,
        // mirroring EIP-712 array hashing.
        bytes32[] memory hashes = new bytes32[](clothing.length);
        for (uint256 i = 0; i < clothing.length; i++) {
            hashes[i] = keccak256(
                abi.encode(
                    STANDARD_CLOTHING_TYPEHASH,
                    _hashTrait(clothing[i].boots),
                    _hashTrait(clothing[i].pants),
                    _hashTrait(clothing[i].shirt),
                    _hashTrait(clothing[i].chest),
                    _hashTrait(clothing[i].waist),
                    _hashTrait(clothing[i].arms),
                    _hashTrait(clothing[i].longShirt),
                    _hashTrait(clothing[i].shoulders),
                    _hashTrait(clothing[i].cloak),
                    clothing[i].bootsOverPants
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
