const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const Sex = {
  Male: 0,
  Female: 1,
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
};

const ALL_COLORS = 0x3ffn;

function defaultTraits() {
  const traits = [];
  const addRange = (sex, traitType, from, to) => {
    for (let traitId = from; traitId <= to; traitId++) {
      traits.push([sex, traitType, traitId, ALL_COLORS]);
    }
  };

  addRange(Sex.Male, TraitType.Arms, 1, 8);
  addRange(Sex.Male, TraitType.Boots, 1, 3);
  addRange(Sex.Male, TraitType.Chest, 1, 3);
  addRange(Sex.Male, TraitType.Hair, 1, 15);
  addRange(Sex.Male, TraitType.HairTail, 7, 7);
  addRange(Sex.Male, TraitType.Hat, 1, 7);
  addRange(Sex.Male, TraitType.LongShirt, 1, 9);
  addRange(Sex.Male, TraitType.Pants, 1, 5);
  addRange(Sex.Male, TraitType.Shirt, 1, 11);
  addRange(Sex.Male, TraitType.Shoulder, 1, 13);
  addRange(Sex.Male, TraitType.Waist, 1, 4);

  addRange(Sex.Female, TraitType.Arms, 1, 7);
  addRange(Sex.Female, TraitType.Boots, 1, 1);
  addRange(Sex.Female, TraitType.Chest, 1, 3);
  addRange(Sex.Female, TraitType.Hair, 1, 15);
  addRange(Sex.Female, TraitType.HairTail, 7, 7);
  addRange(Sex.Female, TraitType.HairTail, 13, 13);
  addRange(Sex.Female, TraitType.Hat, 1, 8);
  addRange(Sex.Female, TraitType.LongShirt, 1, 9);
  addRange(Sex.Female, TraitType.Pants, 1, 10);
  addRange(Sex.Female, TraitType.Shirt, 1, 17);
  addRange(Sex.Female, TraitType.Shoulder, 1, 7);
  addRange(Sex.Female, TraitType.Waist, 1, 2);

  return traits;
}

module.exports = buildModule("SemperlandPersonaModule", (m) => {
  const defaultTraitEntries = m.getParameter("defaultTraitEntries", defaultTraits());

  const semperlandPersona = m.contract("SemperlandPersona", [defaultTraitEntries]);

  return { semperlandPersona };
});
