const { loadFixture, time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const Color = {
  Black: 0,
  Blue: 1,
  DarkBrown: 2,
  Green: 3,
  LightBrown: 4,
  Pink: 5,
  Purple: 6,
  Red: 7,
  White: 8,
  Yellow: 9,
};

const Sex = {
  Male: 0,
  Female: 1,
};

const Body = {
  White: 0,
  Black: 1,
};

const ClothType = {
  Standard: 0,
  Simple: 1,
};

const TraitType = {
  Arms: 0,
  Boots: 1,
  Chest: 2,
  Hair: 3,
  HairTail: 4,
  Hat: 5,
  LongShirt: 6,
  Pants: 7,
  Shirt: 8,
  Shoulder: 9,
  Waist: 10,
  Cloth: 11,
  Necklace: 12,
  Cloak: 13,
};

const ALL_COLORS = 0x3ffn;
const ECDSA = 1;
const EMPTY_TRAIT = { lotId: 0, itemId: 99, color: Color.Yellow };

const TRAIT_TYPEHASH = ethers.keccak256(ethers.toUtf8Bytes("Trait(uint128 lotId,uint120 itemId,uint8 color)"));
const PERSONA_TYPEHASH = ethers.keccak256(
  ethers.toUtf8Bytes(
    "Persona(string name,uint8 sex,uint8 body,uint8 clothType,bytes32 hair,bytes32 hairTail,bytes32 necklace,bytes32 hat)"
  )
);
const SIMPLE_CLOTHING_TYPEHASH = ethers.keccak256(ethers.toUtf8Bytes("SimpleClothing(bytes32 cloth)"));
const STANDARD_CLOTHING_TYPEHASH = ethers.keccak256(
  ethers.toUtf8Bytes(
    "StandardClothing(bytes32 boots,bytes32 pants,bytes32 shirt,bytes32 chest,bytes32 waist,bytes32 arms,bytes32 longShirt,bytes32 shoulders,bytes32 cloak,bool bootsOverPants)"
  )
);

function trait(lotId, itemId, color) {
  return { lotId, itemId, color };
}

function validPersona(name = "Alice_01") {
  return {
    name,
    sex: Sex.Male,
    body: Body.White,
    clothType: ClothType.Simple,
    hair: trait(1, 1, Color.Red),
    hairTail: EMPTY_TRAIT,
    necklace: EMPTY_TRAIT,
    hat: EMPTY_TRAIT,
  };
}

function simpleClothing(cloth = EMPTY_TRAIT) {
  return [{ cloth }];
}

function standardClothing() {
  return [{
    boots: trait(1, 1, Color.Black),
    pants: trait(1, 1, Color.Blue),
    shirt: trait(1, 1, Color.Green),
    chest: EMPTY_TRAIT,
    waist: EMPTY_TRAIT,
    arms: EMPTY_TRAIT,
    longShirt: EMPTY_TRAIT,
    shoulders: EMPTY_TRAIT,
    cloak: EMPTY_TRAIT,
    bootsOverPants: true,
  }];
}

function hashTrait(value) {
  return ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "uint128", "uint120", "uint8"],
      [TRAIT_TYPEHASH, value.lotId, value.itemId, value.color]
    )
  );
}

function hashPersona(value, includeName) {
  return ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "bytes32", "uint8", "uint8", "uint8", "bytes32", "bytes32", "bytes32", "bytes32"],
      [
        PERSONA_TYPEHASH,
        ethers.keccak256(ethers.toUtf8Bytes(includeName ? value.name.toLowerCase() : "")),
        value.sex,
        value.body,
        value.clothType,
        hashTrait(value.hair),
        hashTrait(value.hairTail),
        hashTrait(value.necklace),
        hashTrait(value.hat),
      ]
    )
  );
}

function hashSimpleClothingArray(values) {
  return ethers.keccak256(ethers.concat(values.map((value) => (
    ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(["bytes32", "bytes32"], [SIMPLE_CLOTHING_TYPEHASH, hashTrait(value.cloth)])
    )
  ))));
}

function hashStandardClothingArray(values) {
  return ethers.keccak256(ethers.concat(values.map((value) => (
    ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bool"],
        [
          STANDARD_CLOTHING_TYPEHASH,
          hashTrait(value.boots),
          hashTrait(value.pants),
          hashTrait(value.shirt),
          hashTrait(value.chest),
          hashTrait(value.waist),
          hashTrait(value.arms),
          hashTrait(value.longShirt),
          hashTrait(value.shoulders),
          hashTrait(value.cloak),
          value.bootsOverPants,
        ]
      )
    )
  ))));
}

async function signRegisterFor(contract, signer, target, persona, simple, standard, validSince, validUntil) {
  const network = await ethers.provider.getNetwork();
  const nonce = await contract.nonces(target);
  const authData = "0x";
  const value = {
    target,
    personaHash: hashPersona(persona, true),
    simpleHash: hashSimpleClothingArray(simple),
    standardHash: hashStandardClothingArray(standard),
    validSince,
    validUntil,
    nonce,
    signatureScheme: ECDSA,
    authDataHash: ethers.keccak256(authData),
  };
  const signature = await signer.signTypedData(
    { name: "SemperlandPersona", version: "1", chainId: network.chainId, verifyingContract: await contract.getAddress() },
    {
      RegisterFor: [
        { name: "target", type: "address" },
        { name: "personaHash", type: "bytes32" },
        { name: "simpleHash", type: "bytes32" },
        { name: "standardHash", type: "bytes32" },
        { name: "validSince", type: "uint256" },
        { name: "validUntil", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "signatureScheme", type: "uint8" },
        { name: "authDataHash", type: "bytes32" },
      ],
    },
    value
  );
  return { validSince, validUntil, signatureScheme: ECDSA, authData, signature };
}

describe("SemperlandPersona", function () {
  async function deployFixture() {
    const [owner, alice, bob] = await ethers.getSigners();
    const defaultTraits = [
      [Sex.Male, TraitType.Hair, 1, ALL_COLORS],
      [Sex.Male, TraitType.Boots, 1, ALL_COLORS],
      [Sex.Male, TraitType.Pants, 1, ALL_COLORS],
      [Sex.Male, TraitType.Shirt, 1, ALL_COLORS],
      [Sex.Female, TraitType.Hair, 1, ALL_COLORS],
    ];

    const SemperlandPersona = await ethers.getContractFactory("SemperlandPersona");
    const personas = await SemperlandPersona.deploy(defaultTraits);

    return { personas, owner, alice, bob };
  }

  it("initializes default lot 1 from constructor data", async function () {
    const { personas } = await loadFixture(deployFixture);

    expect(await personas.nextLotId()).to.equal(2);
    expect(await personas.defaultLots(1)).to.equal(true);
    expect(await personas.availableTraits(1, Sex.Male, TraitType.Hair, 1)).to.equal(ALL_COLORS);
  });

  it("validates, normalizes, and reserves persona names", async function () {
    const { personas, alice, bob } = await loadFixture(deployFixture);

    await expect(personas.connect(alice).register(validPersona("1Alice"), simpleClothing(), []))
      .to.be.revertedWithCustomError(personas, "InvalidName");
    await expect(personas.connect(alice).register(validPersona("Al"), simpleClothing(), []))
      .to.be.revertedWithCustomError(personas, "InvalidName");

    await expect(personas.connect(alice).register(validPersona("Alice_01"), simpleClothing(), []))
      .to.emit(personas, "PersonaRegistered")
      .withArgs(alice.address, "alice_01");
    expect(await personas.personasNames("alice_01")).to.equal(alice.address);

    await expect(personas.connect(bob).register(validPersona("ALICE_01"), simpleClothing(), []))
      .to.be.revertedWithCustomError(personas, "NameAlreadyRegistered");
  });

  it("requires matching clothing arguments and available trait colors", async function () {
    const { personas, alice } = await loadFixture(deployFixture);

    await expect(personas.connect(alice).register(validPersona(), [], []))
      .to.be.revertedWithCustomError(personas, "InvalidClothingArguments");

    const unavailable = validPersona("Alice_02");
    unavailable.hair = trait(1, 2, Color.Red);
    await expect(personas.connect(alice).register(unavailable, simpleClothing(), []))
      .to.be.revertedWithCustomError(personas, "InvalidTrait");

    const noObjectMeansEmpty = validPersona("Alice_03");
    noObjectMeansEmpty.hair = EMPTY_TRAIT;
    await expect(personas.connect(alice).register(noObjectMeansEmpty, simpleClothing(), []))
      .to.emit(personas, "PersonaRegistered");
  });

  it("lets the owner register lots, merge colors, and grant custom lot access", async function () {
    const { personas, owner, alice, bob } = await loadFixture(deployFixture);

    await expect(personas.connect(alice).registerTraitsLot("Extra", "ipfs://extra"))
      .to.be.revertedWithCustomError(personas, "OwnableUnauthorizedAccount");

    await personas.connect(owner).registerTraitsLot("Extra", "ipfs://extra");
    await personas.connect(owner).addAvailableTraitColors(2, Sex.Male, TraitType.Necklace, 1, 1n << BigInt(Color.Blue));
    await personas.connect(owner).addAvailableTraitColors(2, Sex.Male, TraitType.Necklace, 1, 1n << BigInt(Color.Red));
    expect(await personas.availableTraits(2, Sex.Male, TraitType.Necklace, 1))
      .to.equal((1n << BigInt(Color.Blue)) | (1n << BigInt(Color.Red)));

    const withNecklace = validPersona("Alice_04");
    withNecklace.necklace = trait(2, 1, Color.Red);
    await expect(personas.connect(alice).register(withNecklace, simpleClothing(), []))
      .to.be.revertedWithCustomError(personas, "InvalidTrait");

    withNecklace.name = "Bob_01";
    await personas.connect(owner).setAllowedLot(bob.address, 2, true);
    await expect(personas.connect(bob).register(withNecklace, simpleClothing(), []))
      .to.emit(personas, "PersonaRegistered");
  });

  it("updates persona traits without changing the name and supports explicit name changes", async function () {
    const { personas, alice } = await loadFixture(deployFixture);

    await personas.connect(alice).register(validPersona("Alice_05"), simpleClothing(), []);
    const next = validPersona("IgnoredName");
    next.clothType = ClothType.Standard;
    await personas.connect(alice).update(next, [], standardClothing());

    const stored = await personas.personas(alice.address);
    expect(stored.name).to.equal("alice_05");
    expect(stored.clothType).to.equal(ClothType.Standard);

    await expect(personas.connect(alice).changeName("Alice_06"))
      .to.emit(personas, "PersonaNameChanged")
      .withArgs(alice.address, "alice_05", "alice_06");
    expect(await personas.personasNames("alice_05")).to.equal(ethers.ZeroAddress);
    expect(await personas.personasNames("alice_06")).to.equal(alice.address);
  });

  it("registers for a target with EIP-712 authorization and rejects replay", async function () {
    const { personas, alice, bob } = await loadFixture(deployFixture);
    const persona = validPersona("Alice_07");
    const simple = simpleClothing();
    const standard = [];
    const now = await time.latest();
    const authorization = await signRegisterFor(
      personas,
      alice,
      alice.address,
      persona,
      simple,
      standard,
      now - 1,
      now + 3600
    );

    await expect(personas.connect(bob).registerFor(alice.address, persona, simple, standard, authorization))
      .to.emit(personas, "PersonaRegistered")
      .withArgs(alice.address, "alice_07");
    expect(await personas.nonces(alice.address)).to.equal(1);

    await expect(personas.connect(bob).registerFor(alice.address, persona, simple, standard, authorization))
      .to.be.revertedWithCustomError(personas, "InvalidSignature");
  });

  it("rejects unsupported delegated signature schemes", async function () {
    const { personas, alice, bob } = await loadFixture(deployFixture);
    const persona = validPersona("Alice_08");
    const simple = simpleClothing();
    const standard = [];
    const now = await time.latest();
    const authorization = await signRegisterFor(
      personas,
      alice,
      alice.address,
      persona,
      simple,
      standard,
      now - 1,
      now + 3600
    );
    authorization.signatureScheme = 2;

    await expect(personas.connect(bob).registerFor(alice.address, persona, simple, standard, authorization))
      .to.be.revertedWithCustomError(personas, "UnsupportedSignatureScheme")
      .withArgs(2);
  });
});
