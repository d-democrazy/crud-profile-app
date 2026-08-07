# ProfileContract — Full Design Document

Consolidated specs, ABI, data flow, and implementation walkthroughs for `ProfileContract.sol`, built function-by-function before writing the contract body.

## Table of Contents

1. [Phase 1: Pre-optimized Contract Design](#phase-1-pre-optimized-contract-design)
    - [ProfileContract — Data Flow Spec](#profilecontract--data-flow-spec)
    - [Part 1 — General Solidity data management concepts](#part-1--general-solidity-data-management-concepts)
    - [Part 2 — This contract's state variables](#part-2--this-contracts-state-variables)
    - [Part 3 — CRUD-by-variable matrix](#part-3--crud-by-variable-matrix)
    - [setProfile()](#setprofile)
    - [updateProfile()](#updateprofile)
    - [getProfile()](#getprofile)
    - [getAllProfile()](#getallprofile)
    - [deleteProfile()](#deleteprofile)
2. [Phase 2: Optimized Contract Design (ProfileContractOp)](#phase-2-optimized-contract-design-profilecontractop)
    - [Why Optimize?](#why-optimize)
    - [Modularization (Interfaces, Libraries, Helpers)](#modularization-interfaces-libraries-helpers)
    - [OpenZeppelin's EnumerableSet](#openzeppelins-enumerableset)
    - [Custom Errors vs Require Strings](#custom-errors-vs-require-strings)
    - [Data Structure Improvements](#data-structure-improvements)
3. [Phase 3: DevOps and Deployment Flow](#phase-3-devops-and-deployment-flow)
    - [Security Best Practice (Keystore)](#security-best-practice-keystore)
    - [Deployment Scripts (Forge)](#deployment-scripts-forge)

---

## Phase 1: Pre-optimized Contract Design

## ProfileContract — Data Flow Spec

### Purpose

Documents the state variables backing `setProfile`, `updateProfile`, `getProfile`, `getAllProfile`, and `deleteProfile` — what each one stores, why it exists, its visibility, and which functions touch it. Read this before implementing function bodies; the function specs assume this data layout.

---

### Part 1 — General Solidity data management concepts

#### Storage locations: `storage`, `memory`, `calldata`

Solidity data lives in one of three places, and the difference matters for both cost and behavior:

| Location   | What it is                                       | Persists across calls? | Typical use                                                           |
| ---------- | ------------------------------------------------ | ---------------------- | --------------------------------------------------------------------- |
| `storage`  | The contract's permanent on-chain state          | Yes                    | State variables (`profiles`, `profileOwners`, `ownerIndex`)           |
| `memory`   | Temporary, erased after the function call ends   | No                     | Local variables inside a function body, return values being assembled |
| `calldata` | Read-only input data from the transaction itself | No (it's the input)    | Function parameters, e.g. `string calldata _name`                     |

Reading `storage` into `memory` (or the reverse, writing `memory` back to `storage`) is an explicit, costed operation — this is why `getAllProfile()` has to loop and copy rather than "just returning" a mapping (mappings can't be copied to memory at all — see below).

#### `mapping` — keyed lookup, not iterable

```solidity
mapping(address => Profile) private profiles;
```

- Gives O(1) lookup by key: `profiles[someAddress]`.
- Every possible key implicitly exists, defaulted to a zero-value struct — there's no concept of "key not present" at the language level; that's why the `Profile.exists` field is needed to distinguish "never set" from "set."
- **Cannot be iterated, cannot report its own length, cannot be copied to `memory` as a whole.** This is the core reason `profileOwners` exists as a separate structure — mappings alone can't answer "give me everything."

#### `array` (dynamic) — ordered, iterable, but linear-cost lookup

```solidity
address[] private profileOwners;
```

- Supports `.length`, `.push()`, `.pop()`, and indexed access `profileOwners[i]`.
- Can be looped over — this is what makes enumeration (`getAllProfile()`) possible at all.
- Finding a _specific_ address's position requires either a linear scan or a side-index (see `ownerIndex` below) — arrays don't give you O(1) "where is X" the way mappings do.

#### Why this contract pairs a mapping with an array

Neither structure alone provides both fast lookup _and_ iteration. This is the standard **enumerable mapping pattern**: `profiles` (mapping) handles "get one record by key" cheaply; `profileOwners` (array) handles "give me all the keys" at all. `ownerIndex` (mapping) exists purely to make _removing_ an entry from `profileOwners` cheap too, otherwise deletion would require scanning the array to find what to remove.

#### `struct` — grouped fields, becomes a tuple at the ABI boundary

```solidity
struct Profile {
    string name;
    string profession;
    string bio;
    uint8 experience;
    bool exists;
}
```

Structs are a Solidity-side convenience for grouping related fields under one name and one storage/memory slot layout. They have **no representation in the ABI** — when a struct crosses the contract boundary (as a function input or output), it's encoded as an ordered **tuple**. This is why front-end code sees `["Jhon Doe", "Software Engineer", ..., true]` instead of a named object — the tuple only carries position, not field names, until a client library (ethers.js/web3.js) re-attaches names using the ABI's `components` metadata.

#### State variable visibility: `private` vs `public`

- `public` state variables get an **auto-generated external getter** with the same name, for free. For a mapping, that getter takes the key as a parameter and returns the raw value — with no ability to add custom logic (like a revert-if-missing guard). For an array, the auto-getter takes an index and returns _one_ element — it does **not** return the whole array.
- `private` state variables have no auto-getter at all — the only way to read them from outside the contract is through functions you write yourself, where you control the guards, filtering, and return shape.

---

### Part 2 — This contract's state variables

#### `profiles`

```solidity
mapping(address => Profile) private profiles;
```

|                 |                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Data scheme** | address → `Profile{name, profession, bio, experience, exists}`                                                                                                                                                                                                                                                                                                                                                                                                         |
| **Visibility**  | `private`                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Why private** | The auto-generated `public` getter for a mapping returns the raw struct for _any_ address — including ones that never registered, silently returning a zeroed-out `Profile{"", "", "", 0, false}` instead of reverting. That undermines the `getProfile()` spec's explicit guard (`require(exists, ...)`). Keeping it `private` forces all external reads through `getProfile()`/`getAllProfile()`, where the "does this actually exist" check is enforced on purpose. |
| **Written by**  | `setProfile` (create), `updateProfile` (patch), `deleteProfile` (clear)                                                                                                                                                                                                                                                                                                                                                                                                |
| **Read by**     | `getProfile`, `getAllProfile`, and internally by all three writers (to check `exists` before acting)                                                                                                                                                                                                                                                                                                                                                                   |

#### `profileOwners`

```solidity
address[] private profileOwners;
```

|                 |                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Data scheme** | Ordered list of addresses that currently have a live profile                                                                                                                                                                                                                                                                                                                                    |
| **Visibility**  | `private`                                                                                                                                                                                                                                                                                                                                                                                       |
| **Why private** | The auto-generated `public` getter for an array only returns _one_ element by index (`profileOwners(2)` → a single address) — it cannot return the whole array in one call, which is the entire point of this variable's existence (enumeration for `getAllProfile()`). A private variable plus a purpose-built `getAllProfile()` function is the only way to expose the full list in one call. |
| **Written by**  | `setProfile` (push on first-time registration), `deleteProfile` (swap-and-pop removal)                                                                                                                                                                                                                                                                                                          |
| **Read by**     | `getAllProfile` (looped over to build the output), and internally by `deleteProfile` (to perform the swap)                                                                                                                                                                                                                                                                                      |

#### `ownerIndex`

```solidity
mapping(address => uint256) private ownerIndex;
```

|                 |                                                                                                                                                                                                                                                                           |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Data scheme** | address → its current position (index) within `profileOwners`                                                                                                                                                                                                             |
| **Visibility**  | `private`                                                                                                                                                                                                                                                                 |
| **Why private** | Pure internal bookkeeping — this value has no meaning to an external caller on its own (an index into an array they can't fetch as a whole anyway). No function spec calls for exposing it, and doing so would leak implementation details of the swap-and-pop mechanism. |
| **Written by**  | `setProfile` (recorded on push), `deleteProfile` (updated for the swapped address, cleared for the deleted address)                                                                                                                                                       |
| **Read by**     | Internally by `deleteProfile` only, to locate the caller's slot in `profileOwners`                                                                                                                                                                                        |

---

### Part 3 — CRUD-by-variable matrix

**C** = Create (first write) · **R** = Read · **U** = Update (overwrite existing) · **D** = Delete (remove/clear)

| Function          | `profiles`                          | `profileOwners`      | `ownerIndex`                                              |
| ----------------- | ----------------------------------- | -------------------- | --------------------------------------------------------- |
| `setProfile()`    | **C**                               | **C** (push)         | **C** (set new index)                                     |
| `updateProfile()` | **U** (patched fields only)         | —                    | —                                                         |
| `getProfile()`    | **R**                               | —                    | —                                                         |
| `getAllProfile()` | **R** (via each `profileOwners[i]`) | **R**                | —                                                         |
| `deleteProfile()` | **D**                               | **D** (swap-and-pop) | **U** (for swapped address) + **D** (for deleted address) |

#### Reading the matrix

- **`profiles`** is touched by every single function — it's the actual data. Every other variable exists only to make reading/writing `profiles` in bulk (or removing an entry) possible.
- **`profileOwners`** is only ever written by the two functions that change _membership_ in the live set — `setProfile` adding, `deleteProfile` removing. `updateProfile` never touches it, since editing an existing profile doesn't change _who's_ registered.
- **`ownerIndex`** has the busiest single function: `deleteProfile()` both updates one entry (the swapped-in address's new position) and deletes another (the removed address's now-meaningless old position) in the same call.

---

## setProfile()

### setProfile() — Spec + ABI

#### Purpose

Create-only setter. Registers a new profile for the caller (`msg.sender`). Does **not** handle updates — a separate `updateProfile()` function will own edits to an existing profile.

#### Mental model decisions

| Question            | Decision                                                                                                  |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| **Key**             | Implicit — `msg.sender` only. No address parameter. Caller can only ever create their own profile.        |
| **Fields**          | `name`, `profession`, `bio` (dynamic `string`, each length-capped) and `experience` (`uint8`, uncapped). |
| **Write semantics** | Create-only. Calling this again after registration must revert, not overwrite.                            |
| **Output**          | None. Confirmation is via the `ProfileSet` event only — no return value.                                  |
| **Guards**          | Revert if `profiles[msg.sender].exists == true`. Revert if any string field exceeds its length cap.       |

#### Length caps

| Field         | Max length     |
| ------------- | -------------- |
| `_name`       | 100 characters  |
| `_profession` | 100 characters  |
| `_bio`        | 500 characters |

#### Function signature

```
setProfile(string,string,string,uint8)
```

**State mutability:** `nonpayable`

#### I/O table

|        | Position | Name          | Type     | Notes                                 |
| ------ | -------- | ------------- | -------- | ------------------------------------- |
| Input  | 0        | `_name`       | `string` | dynamic, ≤ 100 chars                   |
| Input  | 1        | `_profession` | `string` | dynamic, ≤ 100 chars                   |
| Input  | 2        | `_bio`        | `string` | dynamic, ≤ 500 chars                  |
| Input  | 3        | `_experience` | `uint8` | fixed-size, uncapped, max value 255 |
| Output | —        | _(none)_      | —        | no return value                       |

**Implicit key:** `msg.sender` — not part of calldata args, but the storage key everything is written under.

#### Guards (require conditions)

1. `require(!profiles[msg.sender].exists, "Already registered, use update")`
2. `require(bytes(_name).length <= 100, "Name too long")`
3. `require(bytes(_profession).length <= 100, "Profession too long")`
4. `require(bytes(_bio).length <= 500, "Bio too long")`

#### Event emitted

`ProfileSet(address indexed profileOwner, Profile profile)`

#### JSON ABI

##### Function

```json
{
  "type": "function",
  "name": "setProfile",
  "stateMutability": "nonpayable",
  "inputs": [
    { "name": "_name", "type": "string" },
    { "name": "_profession", "type": "string" },
    { "name": "_bio", "type": "string" },
    { "name": "_experience", "type": "uint8" }
  ],
  "outputs": []
}
```

##### Event

```json
{
  "type": "event",
  "name": "ProfileSet",
  "anonymous": false,
  "inputs": [
    {
      "name": "user",
      "type": "address",
      "indexed": true,
      "internalType": "address"
    },
    {
      "name": "name",
      "type": "string",
      "indexed": false,
      "internalType": "string"
    }
  ]
}
```

#### Open follow-up

`updateProfile()` (or similarly named) still needs its own spec, built through the same 5-question mental model — its guard will be the inverse of this one (revert if **not** registered, rather than if already registered).

### setProfile() — Implementation

#### What it does

Creates a brand-new profile for the caller (`msg.sender`). Fails if the caller already has one — this function only handles first-time registration; `updateProfile()` owns edits.

#### State variables it works with

| Variable        | Operation                                                       |
| --------------- | --------------------------------------------------------------- |
| `profiles`      | **Create** — writes a new `Profile` struct under `msg.sender`   |
| `profileOwners` | **Create** — pushes `msg.sender` onto the end                   |
| `ownerIndex`    | **Create** — records `msg.sender`'s position in `profileOwners` |

#### Algorithm — step by step

1. **Validate string lengths** against caps: `_name` ≤ 50, `_profession` ≤ 60, `_bio` ≤ 500 (in bytes). Revert immediately if any is over.
2. **Check registration guard**: `require(!profiles[msg.sender].exists, "Already registered, use update")`.
3. **Record the index this address will occupy**: `ownerIndex[msg.sender] = profileOwners.length` — read _before_ pushing, since `profileOwners.length` at this instant equals the index the new element is about to take.
4. **Push** `msg.sender` onto `profileOwners`.
5. **Write the struct**: `profiles[msg.sender] = Profile({name: _name, profession: _profession, bio: _bio, experience: _experience, exists: true})`.
6. **Emit** `ProfileSet(msg.sender, _name)`.

#### Why this order

- **Guards first, writes last.** All `require` checks run before any storage is touched, so a failing call reverts as early (and cheaply) as possible — no wasted gas partially writing state that then has to unwind.
- **Index captured before push, not after.** `profileOwners.length` changes the instant `push()` runs. Reading it _before_ the push gives exactly the index the new element will land at, with no off-by-one arithmetic (`length - 1`) needed afterward.
- **Length validation before the registration guard** is a minor choice, not a strict requirement — either order works correctly. Doing cheap validation (string length, no storage read) before the state-dependent guard (a storage read) is marginally more gas-efficient on the common failure path of "field too long," but this is a small optimization, not a correctness issue.

#### Diagram

```
BEFORE                                    AFTER setProfile(msg.sender = D)
profileOwners: [A, B, C]                  profileOwners: [A, B, C, D]
                                                            ^ index 3

ownerIndex:                               ownerIndex:
  A -> 0                                    A -> 0
  B -> 1                                    B -> 1
  C -> 2                                    C -> 2
                                             D -> 3   (new)

profiles[D]: (default, exists=false)      profiles[D]: {name, profession, bio,
                                                          experience, exists=true}
```

#### Solidity implementation

```solidity
function setProfile(
    string calldata _name,
    string calldata _profession,
    string calldata _bio,
    uint8 _experience
) external {
    require(bytes(_name).length <= 100, "Name too long");
    require(bytes(_profession).length <= 100, "Profession too long");
    require(bytes(_bio).length <= 500, "Bio too long");

    require(!profiles[msg.sender].exists, "Already registered, use update");

    ownerIndex[msg.sender] = profileOwners.length;
    profileOwners.push(msg.sender);

    profiles[msg.sender] = Profile({
        name: _name,
        profession: _profession,
        bio: _bio,
        experience: _experience,
        exists: true
    });

    emit ProfileSet(msg.sender, _name);
}
```

---

## updateProfile()

### updateProfile() — Spec + ABI

#### Purpose

Partial-patch setter. Updates one or more fields of the caller's (`msg.sender`) **existing** profile. Does not create new profiles — that's `setProfile()`'s job. Fields left at their "no change" sentinel are skipped; only fields actually provided are written.

#### Mental model decisions

| Question            | Decision                                                                                                                                                             |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Key**             | Implicit — `msg.sender` only. No address parameter. Caller can only ever update their own profile.                                                                   |
| **Fields**          | `name`, `profession`, `bio` (dynamic `string`, each length-capped, same caps as `setProfile`) and `experience` (`uint8`, uncapped).                                 |
| **Write semantics** | Partial patch — caller supplies only the fields they want changed.                                                                                                   |
| **Output**          | None. Confirmation is via the `ProfileUpdated` event, which reports which field(s) were patched.                                                                     |
| **Guards**          | Revert if `profiles[msg.sender].exists == false`. Revert if any provided string field exceeds its length cap. Revert if no field was actually provided (no-op call). |

#### Partial-patch sentinel convention

| Field         | Type     | "Not touching this field" signal |
| ------------- | -------- | -------------------------------- |
| `_name`       | `string` | empty string (`""`)              |
| `_profession` | `string` | empty string (`""`)              |
| `_bio`        | `string` | empty string (`""`)              |
| `_experience` | `uint8` | `0`                              |

**Known limitation:** this convention means a caller cannot intentionally clear a string field to empty, or set `experience` to `0` — both values are reserved as "skip this field." Worth flagging if that's ever a real use case; would need a different mechanism (e.g. a bitmask or per-field bool flags) to support it.

#### Length caps (same as `setProfile`)

| Field         | Max length     |
| ------------- | -------------- |
| `_name`       | 100 characters  |
| `_profession` | 100 characters  |
| `_bio`        | 500 characters |

#### Function signature

```
updateProfile(string,string,string,uint8)
```

**State mutability:** `nonpayable`

#### I/O table

|        | Position | Name          | Type     | Notes                             |
| ------ | -------- | ------------- | -------- | --------------------------------- |
| Input  | 0        | `_name`       | `string` | dynamic, ≤ 100 chars, `""` = skip  |
| Input  | 1        | `_profession` | `string` | dynamic, ≤ 100 chars, `""` = skip  |
| Input  | 2        | `_bio`        | `string` | dynamic, ≤ 500 chars, `""` = skip |
| Input  | 3        | `_experience` | `uint8` | fixed-size, uncapped, `0` = skip  |
| Output | —        | _(none)_      | —        | no return value                   |

**Implicit key:** `msg.sender` — the storage entry being patched.

#### Guards (require conditions)

1. `require(profiles[msg.sender].exists, "No profile to update")`
2. `require(bytes(_name).length <= 100, "Name too long")` — only checked if `_name != ""`
3. `require(bytes(_profession).length <= 100, "Profession too long")` — only checked if `_profession != ""`
4. `require(bytes(_bio).length <= 500, "Bio too long")` — only checked if `_bio != ""`
5. `require(bytes(_name).length > 0 || bytes(_profession).length > 0 || bytes(_bio).length > 0 || _experience > 0, "No changes provided")`

#### Event emitted

`ProfileUpdated(address indexed profileOwner, string[] updatedFields)`

Emits the list of field names that were actually patched in this call (e.g. `["name", "bio"]` if only those two were provided), so off-chain listeners know exactly what changed without diffing the whole profile.

#### JSON ABI

##### Function

```json
{
  "type": "function",
  "name": "updateProfile",
  "stateMutability": "nonpayable",
  "inputs": [
    { "name": "_name", "type": "string" },
    { "name": "_profession", "type": "string" },
    { "name": "_bio", "type": "string" },
    { "name": "_experience", "type": "uint8" }
  ],
  "outputs": []
}
```

##### Event

```json
{
  "type": "event",
  "name": "ProfileUpdated",
  "anonymous": false,
  "inputs": [
    {
      "name": "user",
      "type": "address",
      "indexed": true,
      "internalType": "address"
    },
    {
      "name": "fieldsUpdated",
      "type": "string[]",
      "indexed": false,
      "internalType": "string[]"
    }
  ]
}
```

#### Relationship to `setProfile()`

|                             | `setProfile()`                     | `updateProfile()`                                 |
| --------------------------- | ---------------------------------- | ------------------------------------------------- |
| Registration state required | Must **not** be registered         | Must **already** be registered                    |
| Fields required             | All 4, every call                  | Only the ones being changed                       |
| Empty string / zero meaning | Literal value to store             | Sentinel for "skip this field"                    |
| Event                       | `ProfileSet(address, string name)` | `ProfileUpdated(address, string[] fieldsUpdated)` |

### updateProfile() — Implementation

#### What it does

Patches an _existing_ profile. Caller supplies only the fields they want changed — empty string (`""`) for a string field or `0` for `_experience` means "leave this field alone." Emits which fields actually changed.

#### State variables it works with

| Variable        | Operation                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------- |
| `profiles`      | **Update** — only the fields provided are overwritten; the rest of the struct is left as-is |
| `profileOwners` | not touched — membership in the live set doesn't change                                     |
| `ownerIndex`    | not touched — the address's position doesn't change                                         |

#### Algorithm — step by step

1. **Registration guard**: `require(profiles[msg.sender].exists, "No profile to update")`.
2. **Validate lengths** for any _non-empty_ string field: `_name` ≤ 50, `_profession` ≤ 60, `_bio` ≤ 500. Skipped fields (empty string) aren't checked, since nothing is being written for them.
3. **Detect whether anything was actually provided**: at least one of `_name != ""`, `_profession != ""`, `_bio != ""`, `_experience != 0` must be true, or revert `"No changes provided"`.
4. **Apply each provided field individually** by reading the current struct into local storage-pointer access and conditionally overwriting each field:
   - `if (bytes(_name).length > 0) profiles[msg.sender].name = _name;`
   - same pattern for `_profession`, `_bio`
   - `if (_experience != 0) profiles[msg.sender].experience = _experience;`
5. **Build the `fieldsUpdated` list** for the event — this needs a two-pass approach because Solidity `memory` arrays are fixed-size once allocated (no dynamic `.push()` like storage arrays have):
   - **Pass 1**: count how many of the 4 fields were actually provided (0 to 4).
   - **Allocate** a `string[] memory fieldsUpdated` of exactly that size.
   - **Pass 2**: walk the same 4 conditions again, filling the array in order.
6. **Emit** `ProfileUpdated(msg.sender, fieldsUpdated)`.

#### Why this algorithm

- **Per-field conditional writes, not a full struct overwrite.** Since only some fields may be provided, each field needs its own guard before being written — a single `profiles[msg.sender] = Profile({...})` would overwrite untouched fields with empty/zero values, breaking the "partial patch" contract.
- **Two-pass array building is a direct consequence of `memory` arrays being fixed-length.** There's no way to know the array's needed size (0 to 4 elements) without first checking which fields are present — so a count pass has to happen before allocation. This is the same category of constraint that shaped `getAllProfile()`'s two-array output — Solidity forces you to know a `memory` array's size up front.
- **Guards ordered cheapest-check-first**: the registration check (a single storage read) runs before the "no changes provided" check (multiple `bytes(...).length` computations), so the more common/cheaper failure path (not registered) short-circuits fastest.

#### Diagram

```
Call: updateProfile("", "Blockchain Engineer", "", 0)
                      ^skip  ^update              ^skip ^skip

profiles[msg.sender] BEFORE            profiles[msg.sender] AFTER
  name:       "Jean Doe"                 name:       "Jean Doe"        (unchanged)
  profession: "Smart Contract Eng."      profession: "Blockchain Eng." (updated)
  bio:        "Develops secure..."       bio:        "Develops secure..." (unchanged)
  experience: 3                          experience: 3                (unchanged)
  exists:     true                       exists:     true

fieldsUpdated (event) = ["profession"]
```

#### Solidity implementation

```solidity
function updateProfile(
    string calldata _name,
    string calldata _profession,
    string calldata _bio,
    uint8 _experience
) external {
    require(profiles[msg.sender].exists, "No profile to update");

    bool nameProvided = bytes(_name).length > 0;
    bool professionProvided = bytes(_profession).length > 0;
    bool bioProvided = bytes(_bio).length > 0;
    bool experienceProvided = _experience != 0;

    require(
        nameProvided || professionProvided || bioProvided || experienceProvided,
        "No changes provided"
    );

    if (nameProvided) {
        require(bytes(_name).length <= 100, "Name too long");
        profiles[msg.sender].name = _name;
    }
    if (professionProvided) {
        require(bytes(_profession).length <= 100, "Profession too long");
        profiles[msg.sender].profession = _profession;
    }
    if (bioProvided) {
        require(bytes(_bio).length <= 500, "Bio too long");
        profiles[msg.sender].bio = _bio;
    }
    if (experienceProvided) {
        profiles[msg.sender].experience = _experience;
    }

    // Pass 1: count changed fields
    uint256 changedCount = 0;
    if (nameProvided) changedCount++;
    if (professionProvided) changedCount++;
    if (bioProvided) changedCount++;
    if (experienceProvided) changedCount++;

    // Pass 2: fill the fixed-size memory array
    string[] memory fieldsUpdated = new string[](changedCount);
    uint256 i = 0;
    if (nameProvided) fieldsUpdated[i++] = "name";
    if (professionProvided) fieldsUpdated[i++] = "profession";
    if (bioProvided) fieldsUpdated[i++] = "bio";
    if (experienceProvided) fieldsUpdated[i++] = "experience";

    emit ProfileUpdated(msg.sender, fieldsUpdated);
}
```

---

## getProfile()

### getProfile() — Spec + ABI

#### Purpose

Read-only getter. Returns the full profile for a given address. Unlike the setters, the target is explicit — any caller can look up any address's profile, not just their own.

#### Interface decisions

| Question            | Decision                                                                                                                                 |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **Key**             | Explicit — `_user` address parameter. This is a lookup _about_ someone, not _by_ someone, so the caller and the subject are independent. |
| **Fields returned** | The full `Profile` struct: `name`, `profession`, `bio`, `experience`, `exists`.                                                          |
| **Mutability**      | `view` — reads storage only, no gas cost when called externally (off-chain), free for front-ends.                                        |
| **Output**          | The `Profile` struct itself, returned as a tuple.                                                                                        |
| **Guards**          | Revert if `profiles[_user].exists == false` — no silent return of an empty/default struct.                                               |

#### Function signature

```
getProfile(address)
```

**State mutability:** `view`

#### I/O table

|        | Position | Name         | Type      | Notes                                                         |
| ------ | -------- | ------------ | --------- | ------------------------------------------------------------- |
| Input  | 0        | `_user`      | `address` | the profile owner being looked up                             |
| Output | 0        | `name`       | `string`  |                                                               |
| Output | 1        | `profession` | `string`  |                                                               |
| Output | 2        | `bio`        | `string`  |                                                               |
| Output | 3        | `experience` | `uint8`  |                                                               |
| Output | 4        | `exists`     | `bool`    | always `true` in a successful return — call reverts otherwise |

Output is a single `Profile` struct, ABI-encoded as a tuple of the five fields above, in that order.

#### Guards (require conditions)

1. `require(profiles[_user].exists, "No profile for this address")`

No length checks needed — this is a read, not a write; no data is being written or validated for size.

#### Event emitted

None. `view` functions cannot emit events (they don't create a transaction).

#### JSON ABI

##### Function

```json
{
  "type": "function",
  "name": "getProfile",
  "stateMutability": "view",
  "inputs": [{ "name": "_user", "type": "address" }],
  "outputs": [
    {
      "name": "",
      "type": "tuple",
      "internalType": "struct ProfileContract.Profile",
      "components": [
        { "name": "name", "type": "string" },
        { "name": "profession", "type": "string" },
        { "name": "bio", "type": "string" },
        { "name": "experience", "type": "uint8" },
        { "name": "exists", "type": "bool" }
      ]
    }
  ]
}
```

#### Relationship to the setters

|                          | `setProfile()` / `updateProfile()` | `getProfile()`                                       |
| ------------------------ | ---------------------------------- | ---------------------------------------------------- |
| Target                   | Implicit (`msg.sender`)            | Explicit (`_user` param)                             |
| Mutability               | `nonpayable`                       | `view`                                               |
| Cost to caller           | Gas (transaction)                  | Free (off-chain call)                                |
| Missing profile behavior | N/A (guards on registration state) | Reverts rather than returning a default/empty struct |

### getProfile() — Implementation

#### What it does

Looks up a single address's profile and returns it. Reverts if that address has never registered (or has since been deleted), rather than silently returning a zeroed-out struct.

#### State variables it works with

| Variable        | Operation                           |
| --------------- | ----------------------------------- |
| `profiles`      | **Read** — single lookup by `_user` |
| `profileOwners` | not touched                         |
| `ownerIndex`    | not touched                         |

#### Algorithm — step by step

1. **Existence guard**: `require(profiles[_user].exists, "No profile for this address")`.
2. **Return** `profiles[_user]` — Solidity automatically copies the struct from `storage` into the `memory` return value and ABI-encodes it as a tuple.

That's the entire function — no loops, no branching beyond the one guard.

#### Why this algorithm

- **A single storage read is the only operation needed.** Mappings give O(1) lookup by key, and `_user` is already the exact key — there's nothing to search for or iterate over, unlike `getAllProfile()`.
- **The guard exists on purpose, not as a formality.** Without it, calling `getProfile()` on an address that never registered would silently return `Profile{"", "", "", 0, false}` — indistinguishable, from the caller's perspective, from "the person deliberately left every field blank." Reverting forces the caller to explicitly handle "this address has no profile" as an error case rather than a valid-looking empty result.

#### Diagram

```
Caller: getProfile(0xD...)

profiles mapping (storage):
  0xA... -> {name: "Alice", ..., exists: true}
  0xB... -> {name: "Bob",   ..., exists: true}
  0xD... -> {name: "", profession: "", bio: "", experience: 0, exists: false}  (never registered)

Lookup profiles[0xD...] -> exists == false -> REVERT("No profile for this address")
```

#### Solidity implementation

```solidity
function getProfile(address _user) external view returns (Profile memory) {
    require(profiles[_user].exists, "No profile for this address");
    return profiles[_user];
}
```

---

## getAllProfile()

### getAllProfile() — Spec + ABI

#### Purpose

Read-only getter. Returns every address with a currently-live profile, paired with that profile's data. Used by the front-end to render a full directory/list view.

#### Interface decisions

| Question            | Decision                                                                                                                                                                                        |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Key**             | None — no input parameter. Returns the entire live set, not a single lookup.                                                                                                                    |
| **Fields returned** | Two parallel arrays: `owners` (addresses) and `allProfiles` (their `Profile` structs), same index in both arrays refers to the same person.                                                     |
| **Mutability**      | `view` — free for off-chain callers.                                                                                                                                                            |
| **Filtering**       | None needed. `deleteProfile()` performs full cleanup (swap-and-pop) on `profileOwners`, so the array only ever contains addresses with live profiles — no `exists` check required at read time. |
| **Guards**          | None — an empty result (`[], []`) is valid when no profiles exist; this function never reverts.                                                                                                 |

#### Function signature

```
getAllProfile()
```

**State mutability:** `view`

#### I/O table

|        | Position | Name          | Type                    | Notes                        |
| ------ | -------- | ------------- | ----------------------- | ---------------------------- |
| Input  | —        | _(none)_      | —                       |                              |
| Output | 0        | `owners`      | `address[]`             | live profile owners only     |
| Output | 1        | `allProfiles` | `tuple[]` (`Profile[]`) | same order/index as `owners` |

`owners[i]` and `allProfiles[i]` always describe the same person — index alignment is the contract between the two arrays, not an explicit on-chain link.

#### Guards (require conditions)

None. Always succeeds, even with zero registered profiles (returns two empty arrays).

#### Event emitted

None. `view` functions cannot emit events.

#### JSON ABI

##### Function

```json
{
  "type": "function",
  "name": "getAllProfile",
  "stateMutability": "view",
  "inputs": [],
  "outputs": [
    { "name": "owners", "type": "address[]" },
    {
      "name": "allProfiles",
      "type": "tuple[]",
      "internalType": "struct ProfileContract.Profile[]",
      "components": [
        { "name": "name", "type": "string" },
        { "name": "profession", "type": "string" },
        { "name": "bio", "type": "string" },
        { "name": "experience", "type": "uint8" },
        { "name": "exists", "type": "bool" }
      ]
    }
  ]
}
```

#### Implementation note (not part of the ABI, but relevant to the spec)

This function trusts `profileOwners` to already be clean at read time — `deleteProfile()` is responsible for keeping it that way via immediate swap-and-pop removal. This function's body is just a straight loop over `profileOwners`, no `exists` check needed. See `deleteProfile()` spec for how that invariant is maintained (including the `ownerIndex` mapping it relies on).

#### Relationship to `getProfile()`

|                                  | `getProfile()`      | `getAllProfile()`                     |
| -------------------------------- | ------------------- | ------------------------------------- |
| Scope                            | Single address      | Every live address                    |
| Input                            | `_user` (address)   | none                                  |
| Missing/deleted profile behavior | Reverts             | Silently excluded from the result set |
| Output shape                     | One `Profile` tuple | Two parallel arrays                   |

### getAllProfile() — Implementation

#### What it does

Returns every currently-registered address alongside its profile, as two parallel arrays. Relies on `profileOwners` already being accurate (kept that way by `deleteProfile()`'s full cleanup) — no filtering needed here.

#### State variables it works with

| Variable        | Operation                                      |
| --------------- | ---------------------------------------------- |
| `profiles`      | **Read** — once per address in `profileOwners` |
| `profileOwners` | **Read** — the full array, in order            |
| `ownerIndex`    | not touched                                    |

#### Algorithm — step by step

1. **Read the count**: `count = profileOwners.length`.
2. **Allocate** a `memory` array `allProfiles` of exactly `count` size — has to be sized up front since `memory` arrays are fixed-length once created.
3. **Single-pass loop**, `i` from `0` to `count - 1`:
   - Look up `profiles[profileOwners[i]]`.
   - Store it at `allProfiles[i]`.
4. **Return** `(profileOwners, allProfiles)` — `profileOwners` (a `storage` array) is auto-copied to `memory` by Solidity for the return; `allProfiles` was already built in `memory` during the loop.

#### Why this algorithm

- **No filtering step, unlike an earlier design.** An earlier version of this function had to check `profiles[address].exists` on every iteration, because deletions only marked an address as gone without removing it from `profileOwners`. Now that `deleteProfile()` performs full cleanup (swap-and-pop) the moment a profile is deleted, `profileOwners` is guaranteed accurate at all times — so this function can be a plain, unconditional loop. The correctness burden moved entirely to `deleteProfile()`; this function just trusts the invariant it maintains.
- **Single pass, not two.** Because there's no filtering, there's no "count first, then fill" split like `updateProfile()` needs — the final size is already known (`profileOwners.length`), so allocation and filling happen in one straightforward loop.
- **Two parallel arrays rather than an array of address-profile pairs.** Solidity doesn't have a lightweight anonymous pair/tuple type for this — the alternative would be defining a wrapper struct like `struct OwnedProfile { address owner; Profile profile; }` and returning `OwnedProfile[]`. Two parallel arrays avoid that extra type entirely, at the cost of the caller needing to know `owners[i]` and `allProfiles[i]` are linked by index (documented in the function spec).

#### Diagram

```
profileOwners (storage): [A, B, C]

Loop:
  i=0: profiles[A] -> {name: "Alice", ...}   -> allProfiles[0]
  i=1: profiles[B] -> {name: "Bob", ...}     -> allProfiles[1]
  i=2: profiles[C] -> {name: "Carol", ...}   -> allProfiles[2]

Return:
  owners       = [A, B, C]
  allProfiles  = [{Alice-data}, {Bob-data}, {Carol-data}]
                    ^ same index = same person
```

#### Solidity implementation

```solidity
function getAllProfile() external view returns (address[] memory owners, Profile[] memory allProfiles) {
    uint256 count = profileOwners.length;
    owners = profileOwners;
    allProfiles = new Profile[](count);

    for (uint256 i = 0; i < count; i++) {
        allProfiles[i] = profiles[profileOwners[i]];
    }

    // named returns already populated — bare return
}
```

Note: this fixes the unused-`owners`-variable issue flagged earlier in the review of the original contract — `owners` is now actually assigned (`owners = profileOwners`) rather than declared and left untouched while a separate explicit `return (...)` silently supplied the real values.

---

## deleteProfile()

### deleteProfile() — Spec + ABI

#### Purpose

Removes the caller's (`msg.sender`) profile entirely — both the profile data and their entry in the enumerable `profileOwners` list — so `getAllProfile()` never has to filter out stale entries at read time.

#### Interface decisions

| Question                   | Decision                                                                                                                                  |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **Key**                    | Implicit — `msg.sender` only. No address parameter. Caller can only ever delete their own profile.                                        |
| **Fields affected**        | Entire `Profile` struct is cleared (`delete profiles[msg.sender]`).                                                                       |
| **profileOwners handling** | Full cleanup — the caller's address is removed from `profileOwners` immediately via swap-and-pop, not just left stale and filtered later. |
| **Output**                 | `bool` — returns `true` on success.                                                                                                       |
| **Guards**                 | Revert if `profiles[msg.sender].exists == false` — nothing to delete.                                                                     |

#### Function signature

```
deleteProfile()
```

**State mutability:** `nonpayable`

#### I/O table

|        | Position | Name        | Type   | Notes                                                             |
| ------ | -------- | ----------- | ------ | ----------------------------------------------------------------- |
| Input  | —        | _(none)_    | —      | acts on `msg.sender`                                              |
| Output | 0        | _(unnamed)_ | `bool` | `true` on success; function reverts rather than returning `false` |

#### Guards (require conditions)

1. `require(profiles[msg.sender].exists, "Nothing to delete")`

#### Storage side-effects

Since full cleanup was chosen, this function needs an index-tracking structure (`ownerIndex: address → uint256`) to locate the caller's position in `profileOwners` for O(1) swap-and-pop removal, rather than a linear scan. This reintroduces the `ownerIndex` mapping that the earlier 3-variable simplification had dropped — worth confirming that tradeoff (extra storage variable, O(1) delete) is intentional now that `getAllProfile()` no longer needs to filter.

1. `delete profiles[msg.sender]` — clears the profile data and resets `exists` to `false`.
2. Locate `msg.sender`'s index in `profileOwners` via `ownerIndex[msg.sender]`.
3. Move the last address in `profileOwners` into the vacated slot (unless the caller was already last).
4. Update the moved address's entry in `ownerIndex`.
5. `profileOwners.pop()` — array shrinks by one.
6. `delete ownerIndex[msg.sender]`.

#### Event emitted

`ProfileCleared(address indexed user)`

#### JSON ABI

##### Function

```json
{
  "type": "function",
  "name": "deleteProfile",
  "stateMutability": "nonpayable",
  "inputs": [],
  "outputs": [{ "name": "", "type": "bool" }]
}
```

##### Event

```json
{
  "type": "event",
  "name": "ProfileCleared",
  "anonymous": false,
  "inputs": [
    {
      "name": "user",
      "type": "address",
      "indexed": true,
      "internalType": "address"
    }
  ]
}
```

#### Relationship to the other functions

|                             | `setProfile()`   | `updateProfile()`  | `deleteProfile()`            |
| --------------------------- | ---------------- | ------------------ | ---------------------------- |
| Registration state required | Not registered   | Already registered | Already registered           |
| profileOwners effect        | Pushes new entry | None               | Removes entry (swap-and-pop) |
| Output                      | None             | None               | `bool`                       |
| Event                       | `ProfileSet`     | `ProfileUpdated`   | `ProfileCleared`             |

#### Note: reconciling with `getAllProfile()` spec

The `getAllProfile()` spec (written earlier) assumed the simplified approach — filtering by `exists` at read time because `profileOwners` could contain stale addresses. With full cleanup now chosen here, that filtering step becomes unnecessary defensive code: `profileOwners` will always be accurate at read time, since deletion keeps it in sync immediately. `getAllProfile()` can be simplified back to a plain loop with no `exists` check needed. Worth revisiting that spec once this one is finalized, so the two don't describe inconsistent assumptions about the same storage array.

### deleteProfile() — Implementation

#### What it does

Removes the caller's profile entirely, both the data (`profiles`) and their membership in the enumerable list (`profileOwners`), keeping that list accurate so `getAllProfile()` never needs to filter. Returns `true` on success.

#### State variables it works with

| Variable        | Operation                                                             |
| --------------- | --------------------------------------------------------------------- |
| `profiles`      | **Delete** — struct reset to default (`exists` becomes `false`)       |
| `profileOwners` | **Delete** — caller's address removed via swap-and-pop                |
| `ownerIndex`    | **Update** (for the swapped-in address) + **Delete** (for the caller) |

#### Algorithm — step by step

1. **Existence guard**: `require(profiles[msg.sender].exists, "Nothing to delete")`.
2. **Clear the profile data**: `delete profiles[msg.sender]` — resets the whole struct to its zero value, including `exists = false`.
3. **Locate the caller's slot**: `idx = ownerIndex[msg.sender]`.
4. **Locate the last slot**: `lastIdx = profileOwners.length - 1`.
5. **Branch on whether the caller is already last**:
   - **If `idx != lastIdx`** (caller is somewhere in the middle):
     a. Read `lastOwner = profileOwners[lastIdx]`.
     b. Overwrite `profileOwners[idx] = lastOwner` — the last address now occupies the caller's old slot.
     c. Update `ownerIndex[lastOwner] = idx` — so that address's index record matches its new position.
   - **If `idx == lastIdx`** (caller _is_ the last element): skip the swap entirely — nothing needs to move.
6. **Shrink the array**: `profileOwners.pop()` — removes the (now-duplicated, if a swap happened) last slot.
7. **Clear the caller's index record**: `delete ownerIndex[msg.sender]`.
8. **Emit** `ProfileCleared(msg.sender)`.
9. **Return** `true`.

#### Why this algorithm (swap-and-pop, with an index side-table)

- **Swap-and-pop avoids shifting the whole array.** The naive way to remove an element from the middle of an array is to shift every subsequent element down by one — that's O(n) writes for a single deletion. Swap-and-pop instead moves just _one_ element (the last one) into the gap, then shrinks the array — O(1) writes, regardless of array size or where the deleted element was.
- **Order doesn't matter here, so swap-and-pop's one downside is free.** Swap-and-pop doesn't preserve element order (the last address jumps to a new position). For a profile directory where `getAllProfile()` has no promised ordering, that's an acceptable trade for the O(1) win — there'd be a real cost to this choice if the array's order carried meaning (e.g. "registration order"), but nothing in the spec requires that.
- **`ownerIndex` exists purely to make step 3 O(1).** Without it, finding the caller's position in `profileOwners` would require scanning the array linearly (`for i in profileOwners: if profileOwners[i] == msg.sender: break`) — O(n) just to _find_ the slot, before the O(1) swap-and-pop could even begin. The extra mapping trades a small amount of storage (one `uint256` per registered address) for turning the whole delete operation from O(n) to O(1).
- **The `idx == lastIdx` branch is a correctness necessity, not an optimization.** Without it, deleting the _last_ address in the array would read `profileOwners[lastIdx]` (itself), write it back to `profileOwners[idx]` (the same slot, a harmless no-op), but then also try `ownerIndex[lastOwner] = idx` where `lastOwner` is the address about to be deleted — immediately followed by `delete ownerIndex[msg.sender]` undoing that write anyway. It happens to still work by accident in that specific case, but relying on that is fragile; the explicit branch makes the intent clear and avoids relying on the coincidence.

#### Diagram

```
BEFORE — delete C (msg.sender = C)

profileOwners: [A, B, C, D]
                      ^idx=2      lastIdx=3

ownerIndex: A->0, B->1, C->2, D->3

Step 5: swap D into C's slot
profileOwners: [A, B, D, D]   (D temporarily duplicated)
ownerIndex:    D -> 2          (updated)

Step 6: pop the last slot
profileOwners: [A, B, D]

Step 7: clear C's index record
ownerIndex: A->0, B->1, D->2   (C's entry removed)

AFTER
profileOwners: [A, B, D]
profiles[C]:   default/zeroed, exists=false
```

#### Solidity implementation

```solidity
function deleteProfile() external returns (bool) {
    require(profiles[msg.sender].exists, "Nothing to delete");
    delete profiles[msg.sender];

    uint256 idx = ownerIndex[msg.sender];
    uint256 lastIdx = profileOwners.length - 1;

    if (idx != lastIdx) {
        address lastOwner = profileOwners[lastIdx];
        profileOwners[idx] = lastOwner;
        ownerIndex[lastOwner] = idx;
    }

    profileOwners.pop();
    delete ownerIndex[msg.sender];

    emit ProfileCleared(msg.sender);
    return true;
}
```

## Phase 2: Optimized Contract Design (ProfileContractOp)

### Folder Structure and Architecture
When transitioning from the pre-optimized to the optimized contract, the codebase was heavily refactored into a modular architecture to adhere to separation of concerns and DRY (Don't Repeat Yourself) principles.

```
src/
├── helpers/
│   ├── CompareHelper.sol
│   └── ValidationHelper.sol
├── interfaces/
│   └── IProfileContractOp.sol
├── libraries/
│   └── ProfileTypes.sol
├── ProfileContract.sol (Phase 1)
└── ProfileContractOp.sol (Phase 2)
```

**Why architect it this way?**
1. **`interfaces/`**: By extracting the ABI, Custom Errors, and Events into `IProfileContractOp.sol`, we create a clean boundary. Other contracts and front-ends can easily import just the interface without dragging in the entire logic bytecode.
2. **`libraries/`**: The `ProfileTypes.sol` library centralizes shared definitions (like `Profile` and `ProfileInput` structs, and the `Field` enum). This eliminates redundancy and keeps the main contract file focused on state and behavior rather than data structure definitions.
3. **`helpers/`**: Abstract contracts like `ValidationHelper.sol` and `CompareHelper.sol` house reusable internal and pure logic (e.g., string length validation and keccak256 comparison). By abstracting these, `ProfileContractOp`'s main functions become drastically smaller and easier to read.
4. **`ProfileContractOp.sol`**: The main contract now acts simply as a coordinator—orchestrating storage reads/writes while leaning on the helpers and libraries for processing.

---

### Deep Dive: Libraries, Interfaces, and Helpers

To mirror the function-by-function pedagogical breakdown, here is the exact structural rationale for each abstracted module.

#### 1. Libraries (`ProfileTypes.sol`)

**What it is**
A Solidity `library` used solely as a central repository for shared data types. It contains the `Field` enum, `Profile` struct, and the `ProfileInput` struct.

**Why it's needed**
In Phase 1, `struct Profile` was defined inside the contract. If a frontend or another smart contract wanted to interact with `ProfileContract`, they would have to import the entire contract just to know what a `Profile` looks like. By extracting this into `ProfileTypes.sol`, any file (interfaces, helpers, main contract, deployment scripts) can import just the structs without inheriting any logic or storage overhead. Furthermore, bundling inputs into `ProfileInput` avoids "Stack too deep" errors when passing numerous strings to `setProfile`.

**How it works (Implementation)**
```solidity
library ProfileTypes {
    enum Field { Name, Profession, Bio, Experience }

    struct Profile {
        string name;
        string profession;
        string bio;
        uint8 experience;
        bool exists;
    }

    struct ProfileInput {
        string name;
        string profession;
        string bio;
        uint8 experience;
    }
}
```
*Usage in main contract*: `import {ProfileTypes} from "./libraries/ProfileTypes.sol";` allows `ProfileTypes.Profile storage profile = profiles[msg.sender];`.

#### 2. Interfaces (`IProfileContractOp.sol`)

**What it is**
An `interface` defines the external API of a smart contract without implementing any of the logic. It dictates exactly which functions, custom errors, and events the implementing contract *must* have.

**Why it's needed**
- **Abstraction & Decoupling**: If you build a dapp that interacts with the Profile App, your dapp's smart contracts only need to know the *interface* of the profile contract, not its implementation.
- **Custom Errors**: Defining `error ProfileAlreadyExists();` inside the interface ensures that anyone interacting with the contract knows exactly which errors to decode if a transaction reverts. 
- **Gas Efficiency**: Custom errors in an interface are strictly cheaper than `require(..., "String")` because they don't store long strings in the deployed bytecode.

**How it works (Implementation)**
```solidity
interface IProfileContractOp {
    error ProfileAlreadyExists();
    error ProfileNotFound();
    error NoChanges();

    event ProfileSet(address indexed profileOwner, ProfileTypes.Profile profile);
    event ProfileUpdated(address indexed profileOwner, string[] updatedFields, ProfileTypes.Profile profile);
    event ProfileCleared(address indexed profileOwner);

    function setProfile(ProfileTypes.ProfileInput calldata input) external;
    function updateProfile(ProfileTypes.ProfileInput calldata input) external;
    function deleteProfile() external returns (bool);
    function getProfile(address profileOwner) external view returns (ProfileTypes.Profile memory);
    function getAllProfiles() external view returns (address[] memory, ProfileTypes.Profile[] memory);
}
```
*Usage in main contract*: `contract ProfileContractOp is IProfileContractOp { ... }`. The compiler forces `ProfileContractOp` to implement all these functions exactly as defined.

#### 3. Helpers (`ValidationHelper.sol` & `CompareHelper.sol`)

**What they are**
Abstract contracts that house internal, pure utility functions. 

**Why they are needed**
In Phase 1, `setProfile` and `updateProfile` were cluttered with repetitive `require(bytes(_name).length <= 100)` statements. Every string field needed identical validation logic. Furthermore, `updateProfile` needed complex `keccak256` logic to check if a string had changed before issuing an `SSTORE`. 
By abstracting these into `ValidationHelper` and `CompareHelper`:
- The main contract becomes drastically shorter and strictly focused on state manipulation.
- We adhere to DRY principles. If the logic for validating a string needs to change, it is changed in one place.

**How they work (Implementation)**

**ValidationHelper.sol**
```solidity
abstract contract ValidationHelper {
    error RequiredField(ProfileTypes.Field field);
    error MaxLengthExceeded(ProfileTypes.Field field, uint256 maxLength);

    function _validateRequiredString(string calldata value, ProfileTypes.Field field, uint256 maxLength) internal pure {
        uint256 length = bytes(value).length;
        if (length == 0) revert RequiredField(field);
        if (length > maxLength) revert MaxLengthExceeded(field, maxLength);
    }
}
```
*Usage*: `_validateRequiredString(input.name, ProfileTypes.Field.Name, 100);` replaces 3 lines of messy requires.

**CompareHelper.sol**
```solidity
abstract contract CompareHelper {
    function _isDifferent(string calldata input, string storage current) internal pure returns (bool) {
        return keccak256(bytes(input)) != keccak256(bytes(current));
    }
}
```
*Usage*: `if (_isDifferent(input.name, profile.name)) { profile.name = input.name; }` allows us to securely and cheaply verify string mutations before burning gas on storage writes.


---

### ProfileContractOp — Data Flow Spec

#### Part 1 — Optimization Concepts

**Custom Errors over Require Strings**
Instead of `require(..., "String")`, the contract uses custom errors like `revert ProfileAlreadyExists()`. Custom errors are ABI-encoded (essentially a 4-byte selector plus any arguments), making them significantly cheaper to deploy and execute on failure than storing and reverting with dynamic string messages.

**ProfileInput Struct**
Functions like `setProfile` and `updateProfile` previously took 4 separate parameters. This was refactored into a single `ProfileTypes.ProfileInput calldata input`. Passing a single struct drastically reduces "Stack too deep" issues and creates a cleaner function signature.

#### Part 2 — This contract's state variables

**`profiles`**
```solidity
mapping(address => ProfileTypes.Profile) private profiles;
```
Same as Phase 1. Maps an address to its `Profile` struct.

**`profileOwners` (EnumerableSet)**
```solidity
EnumerableSet.AddressSet private profileOwners;
```
This is a massive optimization. We removed both the manual `address[] profileOwners` array and the `mapping(address => uint256) ownerIndex`. OpenZeppelin's `EnumerableSet` handles the underlying array and index mapping implicitly, offering gas-efficient O(1) `add()`, `remove()`, and `contains()` operations.

#### Part 3 — CRUD-by-variable matrix (Optimized)

| Function          | `profiles`                          | `profileOwners` (EnumerableSet)      |
| ----------------- | ----------------------------------- | ------------------------------------ |
| `setProfile()`    | **C**                               | **C** (add)                          |
| `updateProfile()` | **U** (patched fields only)         | —                                    |
| `getProfile()`    | **R**                               | **R** (contains guard)               |
| `getAllProfiles()`| **R**                               | **R** (values export)                |
| `deleteProfile()` | **D**                               | **D** (remove)                       |

---

### setProfile() (Optimized)

#### Spec + ABI
Registers a new profile for the caller, heavily relying on the `ValidationHelper` for string assertions and `EnumerableSet` for safe tracking.

**I/O table**
| Input | `input` | `ProfileTypes.ProfileInput` | struct containing name, profession, bio, experience |

**Guards**
1. `if (profiles[msg.sender].exists) revert ProfileAlreadyExists();`
2. Handled by `ValidationHelper`: max lengths enforced (name: 100, profession: 50, bio: 500). Wait, the code says profession 50. We respect the optimized code limits exactly.
3. `if (input.experience == 0) revert RequiredField(...)`

#### Implementation
1. **Existence Guard**: Checks if profile already exists.
2. **Validate Strings**: Calls `_validateRequiredString` for name, profession, and bio.
3. **Validate Experience**: Ensures it's non-zero.
4. **State Update**: Calls `profileOwners.add(msg.sender)` (O(1) insertion) and assigns the `Profile` struct to `profiles[msg.sender]`.
5. **Emit Event**: `ProfileSet`.

**Solidity implementation**
```solidity
function setProfile(ProfileTypes.ProfileInput calldata input) external {
    if (profiles[msg.sender].exists) {
        revert ProfileAlreadyExists();
    }

    _validateRequiredString(input.name, ProfileTypes.Field.Name, 100);
    _validateRequiredString(input.profession, ProfileTypes.Field.Profession, 50);
    _validateRequiredString(input.bio, ProfileTypes.Field.Bio, 500);
    if (input.experience == 0) revert RequiredField(ProfileTypes.Field.Experience);

    profileOwners.add(msg.sender);
    profiles[msg.sender] = ProfileTypes.Profile({
        name: input.name, profession: input.profession, bio: input.bio, experience: input.experience, exists: true
    });

    emit ProfileSet(msg.sender, profiles[msg.sender]);
}
```

---

### updateProfile() (Optimized)

#### Spec + ABI
Updates an existing profile. Significantly optimized to only perform `SSTORE` (storage writes) if the value genuinely changed, using `keccak256` comparisons.

#### Implementation
1. **Existence Guard**: Reverts with `ProfileNotFound` if not registered.
2. **Conditional Updates**: For each field (name, profession, bio):
   - Check if provided `bytes(input.field).length != 0`.
   - Validate length via `_validateRequiredString`.
   - Compare new vs old string using `_isDifferent(input.field, profile.field)` from `CompareHelper`.
   - If different, update state and track in `updatedFields`.
3. **Change Tracking via Assembly**: Because memory arrays are fixed-length, we allocate `string[] memory updatedFields = new string[](4);`. After checking all 4 fields, we might have fewer than 4 changes (e.g., `changedCount = 2`). Instead of leaving empty slots, inline assembly is used: `assembly { mstore(updatedFields, changedCount) }` to dynamically shrink the array's length header in memory before emitting it.
4. **No Changes Guard**: `if (changedCount == 0) revert NoChanges();`

**Solidity implementation**
```solidity
function updateProfile(ProfileTypes.ProfileInput calldata input) external {
    ProfileTypes.Profile storage profile = profiles[msg.sender];
    if (!profile.exists) {
        revert ProfileNotFound();
    }

    string[] memory updatedFields = new string[](4);
    uint8 changedCount;

    if (bytes(input.name).length != 0) {
        _validateRequiredString(input.name, ProfileTypes.Field.Name, 100);
        if (_isDifferent(input.name, profile.name)) {
            profile.name = input.name;
            updatedFields[changedCount++] = "name";
        }
    }
    // ... same for profession, bio, experience ...

    if (changedCount == 0) revert NoChanges();

    // Dynamically shrink the memory array length before emitting
    assembly {
        mstore(updatedFields, changedCount)
    }

    emit ProfileUpdated(msg.sender, updatedFields, profile);
}
```

---

### getProfile() (Optimized)

#### Spec + ABI
Reads a single profile. Unlike Phase 1 which checked `profiles[_user].exists`, the optimized contract uses the EnumerableSet.

#### Implementation
```solidity
function getProfile(address profileOwner) external view returns (ProfileTypes.Profile memory) {
    if (!profileOwners.contains(profileOwner)) {
        revert ProfileNotFound();
    }
    return profiles[profileOwner];
}
```

---

### getAllProfiles() (Optimized)

#### Spec + ABI
Returns parallel arrays of addresses and their respective profiles. Note the plural name `getAllProfiles` compared to Phase 1's `getAllProfile`.

#### Implementation
The `EnumerableSet` exposes a `.values()` function that conveniently exports the entire underlying address array into memory in one shot. We then allocate the `Profile[]` array and loop through.

```solidity
function getAllProfiles() external view returns (address[] memory, ProfileTypes.Profile[] memory) {
    uint256 length = profileOwners.length();
    address[] memory owners = profileOwners.values();
    ProfileTypes.Profile[] memory allProfiles = new ProfileTypes.Profile[](length);

    for (uint256 i; i < length; i++) {
        allProfiles[i] = profiles[owners[i]];
    }
    return (owners, allProfiles);
}
```

---

### deleteProfile() (Optimized)

#### Spec + ABI
Clears the user's profile and removes them from the tracking list.

#### Implementation
The massive manual swap-and-pop logic from Phase 1 has been completely eliminated. `EnumerableSet` handles all of the O(1) shifting under the hood via `profileOwners.remove(msg.sender)`.

```solidity
function deleteProfile() external returns (bool) {
    if (!profiles[msg.sender].exists) {
        revert ProfileNotFound();
    }
    delete profiles[msg.sender];
    profileOwners.remove(msg.sender);

    emit ProfileCleared(msg.sender);
    return true;
}
```

---

## Phase 3: DevOps and Deployment Flow

### Security Best Practice (Keystore)
When deploying contracts, managing private keys securely is paramount. It is a critical anti-pattern to paste private keys as plain text inside a `.env` file or directly into terminal commands. Instead, we use Foundry's keystore system combined with the `--account` flag.

#### Step-by-Step Keystore Setup
You have two safe options to configure a secure wallet with `cast`:

**Option 1: Generate a brand new wallet directly into the keystore**
Run this command to create a new random keypair and automatically encrypt it in the default Foundry keystore directory (`~/.foundry/keystores`):
```bash
cast wallet new ~/.foundry/keystores/<account_name>
```
You will be prompted to enter a password to encrypt the keystore file. 

**Option 2: Import an existing private key interactively**
If you already have a private key, securely import it without saving it to your bash history:
```bash
cast wallet import <account_name> --interactive
```
1. You will be prompted to paste your private key.
2. Then, you will provide a password to encrypt it.

#### Deploying with the Keystore
In the `Makefile`, you can observe the use of `--account dummy` (where `dummy` is the placeholder for your `<account_name>`).
When you run:
```bash
make deploy
```
Foundry will detect the `--account` flag and prompt you for your keystore password interactively. This completely eliminates plain-text private key exposure.

### Deployment Scripts (Forge)
Foundry utilizes Solidity itself for scripting deployments, which lives in the `script` directory. 
- **`DeployProfileContract.s.sol` and `DeployProfileContractOp.s.sol`**: Both scripts inherit from Forge's `Script` contract.
- **`vm.startBroadcast()` / `vm.stopBroadcast()`**: Everything between these two cheatcodes generates actual transactions that get broadcasted to the network.
- **Environment Variables**: Variables like API URLs are safely pulled using `vm.envString("CORESCAN_TESTNET2")`.

---

### Best Practice: Leverage a Makefile

A `Makefile` is a first-class DevOps tool and an essential part of a professional Foundry project. Alongside keystores, it is the second pillar of secure, repeatable deployments.

---

#### What is a Makefile?

A `Makefile` is a plain text file (named exactly `Makefile`, no extension) that tells the `make` build-automation program how to assemble targets from rules. Each **target** is a named task, and each task contains one or more shell commands that `make` will execute.

The core syntax is:

```makefile
target-name: [optional-dependencies]
	shell command goes here
	another shell command
```

> **Critical syntax rule**: The indentation before shell commands **must be a real tab character** (`\t`), not spaces. Most editors can be configured to insert tabs when working in Makefiles.

`make` was originally designed to compile C programs, but its simple "name → commands" model makes it equally powerful as a task runner for Foundry projects—similar to how Node.js projects use `npm run` scripts.

---

#### Why Leverage a Makefile?

| Problem without a Makefile | How a Makefile solves it |
|---|---|
| Forge deployment commands are long, multi-flag one-liners that are easy to mis-type | A short `make deploy` hides the complexity |
| Every developer might use slightly different flags (wrong RPC URL, missing `--legacy`) | The Makefile is the single source of truth for every command |
| Environment secrets need to be loaded before the command runs | `include .env` + `export` at the top of the Makefile auto-loads `.env` into every target |
| Plain-text private keys in `.env` or terminal history | `--account <name>` delegates to the encrypted keystore; the Makefile never sees the key |
| Forgetting to broadcast after a simulation | The `deploy` target always includes `--broadcast` by design |
| Complex verification steps (parsing JSON, calling the verifier API) | Encapsulated once in the `verify` target and reused forever |

In short: **a Makefile is reproducibility-as-code**. Anyone who clones the repo runs the exact same workflow with `make deploy`.

---

#### How to Write the Makefile — Step-by-Step

Below is a full walkthrough of the `Makefile` in this project, built up piece by piece.

---

##### Step 1 — Load and Export Environment Variables

```makefile
include .env
export
```

- `include .env` reads every `KEY=VALUE` line from `.env` into `make`'s variable namespace.
- `export` re-exports all those variables to the shell environment so that every command spawned inside a target (e.g., `forge`, `jq`) can read them as normal `$VARIABLE` shell variables.

Your `.env` should contain non-secret config only—RPC URLs, API endpoints, API keys for the block explorer:

```
TESTNET2_RPC_URL=https://rpc.testnet2.example.com
TESTNET2_API_URL=https://api.testnet2.example.com
CORESCAN_TESTNET2_API_KEY=abc123
```

> **Never put a raw private key in `.env`.** Add `.env` to `.gitignore` and use the keystore for signing.

---

##### Step 2 — Define Shared Variables

```makefile
CONTRACT_NAME := ProfileContractOp
SCRIPT_NAME   := DeployProfileContractOp.s.sol
SCRIPT_PATH   := script/$(SCRIPT_NAME):DeployProfileContractOp
```

- `:=` is the immediate-assignment operator in `make`—the value is expanded once at parse time, not every time the variable is used.
- `$(VARIABLE)` is how you dereference a variable inside a Makefile.
- `SCRIPT_PATH` uses the Forge convention `<file_path>:<contract_name>` to tell `forge script` which specific contract to run inside the script file.

If you rename your contract or script in the future, you update exactly one line here and all targets stay correct.

---

##### Step 3 — Declare `.PHONY` Targets

```makefile
.PHONY: deploy verify tdeploy
```

By default, `make` checks whether a file with the target's name already exists. If it does, and the file is newer than its dependencies, `make` skips running the target. For pure task targets like `deploy` and `verify`, there will never be an output file, but `make` could still get confused if a file named `deploy` ever appeared in the directory. `.PHONY` explicitly tells `make` "this is always a command, never a file".

---

##### Step 4 — Write the `tdeploy` Target (Local Testnet)

```makefile
tdeploy:
	forge script $(SCRIPT_PATH) \
		--rpc-url http://127.0.0.1:8545 \
		--account dummy \
		--broadcast \
		--legacy
```

- **`tdeploy`** stands for "test deploy". It targets the local Anvil chain (`127.0.0.1:8545`).
- The backslash `\` at the end of each line is a line-continuation character—it tells the shell that the command continues on the next line. This keeps long commands readable.
- `--account dummy` references the keystore entry named `dummy` (created with `cast wallet import dummy --interactive`). Foundry will prompt for the decryption password at runtime.
- `--broadcast` submits the transactions; without this flag, `forge script` only simulates.
- `--legacy` disables EIP-1559 transaction formatting, required for some EVM-compatible chains that don't support it.

| Flag | Purpose |
|---|---|
| `--rpc-url` | Which node to send transactions to |
| `--account` | Encrypted keystore name (no plain-text key) |
| `--broadcast` | Actually send transactions (default is simulation-only) |
| `--legacy` | Use pre-EIP1559 gas model |

---

##### Step 5 — Write the `deploy` Target (Live Testnet)

```makefile
deploy:
	forge script $(SCRIPT_PATH) \
		--rpc-url $(TESTNET2_RPC_URL) \
		--account dummy \
		--broadcast \
		--legacy
```

Identical to `tdeploy` except `--rpc-url` now reads `$(TESTNET2_RPC_URL)` from `.env` instead of being hardcoded. This is the single change that distinguishes a local deploy from a live one—everything else is identical.

---

##### Step 6 — Write the `verify` Target

This is the most sophisticated target. Verification submits your contract's Solidity source code to a block explorer so users can read and audit it on-chain.

```makefile
verify:
	$(eval BROADCAST_FILE := $(shell find broadcast/$(SCRIPT_NAME) -name run-latest.json | head -n 1))
	$(eval CONTRACT := $(shell jq -r '.transactions[] | select(.contractName == "$(CONTRACT_NAME)") | .contractAddress' $(BROADCAST_FILE)))
	@echo "Broadcast file: $(BROADCAST_FILE)"
	@echo "Verifying $(CONTRACT_NAME) at $(CONTRACT)"
	forge verify-contract $(CONTRACT) $(CONTRACT_NAME) \
		--verifier-url $(TESTNET2_API_URL) \
		--api-key $(CORESCAN_TESTNET2_API_KEY) \
		--watch
```

Let's break down each line:

**Line 1 — `$(eval BROADCAST_FILE := ...)`**
`forge script --broadcast` writes a JSON receipt of every transaction to `broadcast/<ScriptName>/<chainId>/run-latest.json`. The `$(shell ...)` function runs a shell command during `make` evaluation and returns its output as a string. Here `find` locates that JSON file automatically regardless of the chain ID directory name.

**Line 2 — `$(eval CONTRACT := ...)`**
`jq` is a command-line JSON processor. This command queries the broadcast JSON for the transaction whose `contractName` matches `$(CONTRACT_NAME)` and extracts its deployed `contractAddress`. This means you never need to copy-paste the deployed address manually.

**Lines 3–4 — `@echo ...`**
The `@` prefix suppresses `make` echoing the command itself before running it—only the output is shown. This keeps the terminal output clean.

**Lines 5–8 — `forge verify-contract`**
Sends the source, compiler settings, and ABI to the block explorer API. `--watch` polls the explorer until verification succeeds (or fails), printing the result.

---

##### Step 7 (Optional) — Add a `setup-wallet` Target

```makefile
setup-wallet:
	@echo "Creating a new encrypted keystore wallet..."
	cast wallet new ~/.foundry/keystores/dummy
	@echo "Wallet saved. Use 'make deploy' to deploy with it."
```

Running `make setup-wallet` creates a new random keypair, encrypts it with a password you provide interactively, and saves it to the Foundry keystore directory under the name `dummy`. This is a one-time setup step for any new developer joining the project.

---

#### Visual Target Dependency Diagram

```
[.env] ──────────────────────────────────────────────────┐
                                                          │  (loaded by include .env)
[Makefile variables]                                      ▼
  CONTRACT_NAME ─────────────────────────────────── verify
  SCRIPT_NAME   ─────────────────────────────────── verify
  SCRIPT_PATH   ─────┬─────── tdeploy              deploy
                     └─────── deploy
                                  │
                          forge script ...
                                  │
                       broadcast/run-latest.json
                                  │
                               verify
                                  │
                        forge verify-contract ...
```

---

#### How to Use the Makefile

After completing the keystore setup (see Keystore section above), all operations reduce to a single short command.

**First-time setup (one-time per machine)**
```bash
make setup-wallet   # creates the encrypted 'dummy' keystore
```

**Deploy to local Anvil (development)**
```bash
make tdeploy        # targets http://127.0.0.1:8545
```

**Deploy to live testnet**
```bash
make deploy         # uses TESTNET2_RPC_URL from .env
```

**Verify on block explorer**
```bash
make verify         # auto-reads deployed address from broadcast JSON
```

**Chain deploy + verify in one line**
```bash
make deploy && make verify
```

---

#### Makefile Best-Practice Checklist

- [ ] `include .env` and `export` at the top so all targets see your config.
- [ ] Add `.env` to `.gitignore`—never commit secrets to version control.
- [ ] Use `--account <name>` (keystore) instead of `--private-key $PRIVATE_KEY`.
- [ ] Declare all task targets in `.PHONY` to avoid file-name conflicts.
- [ ] Use `:=` variables for reusable values (contract name, script path).
- [ ] Use line continuations (`\`) to keep long Forge commands readable.
- [ ] Prefix informational `echo` lines with `@` to suppress command noise.
- [ ] Pin your Foundry version in `foundry.toml` (`solc = "0.8.28"`) so the Makefile produces the same bytecode on every machine.
- [ ] Provide a `help` target (optional) that prints available commands:
  ```makefile
  help:
  	@echo "Available targets:"
  	@echo "  setup-wallet  Create an encrypted keystore wallet"
  	@echo "  tdeploy       Deploy to local Anvil"
  	@echo "  deploy        Deploy to live testnet"
  	@echo "  verify        Verify contract on block explorer"
  ```

