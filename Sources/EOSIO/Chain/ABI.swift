//
//  ABI.swift
//  EOSIO
//
//  Created by Johan Nordberg on 2019-10-15.
//

import Foundation

/// Type describing a EOSIO ABI defenition.
public struct ABI: Equatable, Hashable {
    /// The ABI defenition version.
    public let version: String
    /// List of type aliases.
    public var types: [TypeDef]
    /// List of variant types.
    public var variants: [Variant]
    /// List of struct types.
    public var structs: [Struct]
    /// List of contract actions.
    public var actions: [Action]
    /// List of contract tables.
    public var tables: [Table]
    /// Ricardian contracts.
    public var ricardianClauses: [Clause]

    /// Create a new ABI specification.
    public init(
        types: [TypeDef] = [],
        variants: [Variant] = [],
        structs: [Struct] = [],
        actions: [Action] = [],
        tables: [Table] = [],
        ricardianClauses: [Clause] = []
    ) {
        self.version = "eosio::abi/1.1"
        self.types = types
        self.variants = variants
        self.structs = structs
        self.actions = actions
        self.tables = tables
        self.ricardianClauses = ricardianClauses
    }

    public final class ResolvedType: CustomStringConvertible {
        public let name: String
        public let flags: Flags

        public var parent: ResolvedType?
        public var builtIn: BuiltIn?
        public var variant: [ResolvedType]?
        public var fields: [(name: String, type: ResolvedType)]?
        public var other: ResolvedType?

        public enum BuiltIn: String {
            case asset
            case symbol
            case name
            case uint8
            case uint16
            case uint32
            case uint64
            case int8
            case int16
            case int32
            case int64
            case string
            case checksum256
        }

        public struct Flags: OptionSet {
            public let rawValue: UInt8
            public init(rawValue: UInt8) { self.rawValue = rawValue }
            public static let optional = Flags(rawValue: 1 << 0)
            public static let array = Flags(rawValue: 1 << 1)
            public static let binaryExt = Flags(rawValue: 1 << 2)
        }

        init(_ name: String, _ flags: Flags) {
            self.name = name
            self.flags = flags
        }

        public var description: String {
            var rv = "ResolvedType("
            if self.variant != nil {
                rv += "variant: "
            } else if self.fields != nil {
                rv += "struct: "
            }
            rv += self.name
            if self.flags.contains(.array) {
                rv += "[]"
            }
            if self.flags.contains(.optional) {
                rv += "?"
            }
            if self.flags.contains(.binaryExt) {
                rv += "$"
            }
            return rv + ")"
        }
    }

    public func resolveType(_ name: String) -> ResolvedType {
        var seen = [String: ResolvedType]()
        return self.resolveType(name, nil, &seen)
    }

    func resolveTypeName(_ name: String) -> (String, ResolvedType.Flags) {
        var name = name
        var flags: ResolvedType.Flags = []
        if name.hasSuffix("$") {
            name.removeLast()
            flags.insert(.binaryExt)
        }
        if name.hasSuffix("?") {
            name.removeLast()
            flags.insert(.optional)
        }
        if name.hasSuffix("[]") {
            name.removeLast(2)
            flags.insert(.array)
        }
        return (self.resolveTypeAlias(name), flags)
    }

    func resolveType(_ name: String, _ parent: ResolvedType?, _ seen: inout [String: ResolvedType]) -> ResolvedType {
        let res = self.resolveTypeName(name)
        let type = ResolvedType(res.0, res.1)
        type.parent = parent
        if let existing = seen[name] {
            type.other = existing
            return type
        }
        seen[name] = type
        if let fields = self.resolveStruct(type.name) {
            type.fields = fields.map { ($0.name, self.resolveType($0.type, type, &seen)) }
        } else if let variant = self.getVariant(type.name) {
            type.variant = variant.types.map { self.resolveType($0, parent, &seen) }
        } else if let builtIn = ResolvedType.BuiltIn(rawValue: type.name) {
            type.builtIn = builtIn
        }
        return type
    }

    func resolveTypeAlias(_ name: String) -> String {
        // TODO: handle more than 1 to 1 aliases
        return self.types.first(where: { $0.newTypeName == name })?.type ?? name
    }

    public func resolveStruct(_ name: String) -> [ABI.Field]? {
        var top = self.getStruct(name)
        if top == nil { return nil }
        var rv: [ABI.Field] = []
        var seen = Set<String>()
        repeat {
            rv.insert(contentsOf: top!.fields, at: 0)
            seen.insert(top!.name)
            if seen.contains(top!.base) {
                return nil // circular ref
            }
            top = self.getStruct(top!.base)
        } while top != nil
        return rv
    }

    public func getStruct(_ name: String) -> ABI.Struct? {
        return self.structs.first { $0.name == name }
    }

    public func getVariant(_ name: String) -> ABI.Variant? {
        return self.variants.first { $0.name == name }
    }
}

// MARK: ABI Defenition Types

public extension ABI {
    struct TypeDef: ABICodable, Equatable, Hashable {
        public let newTypeName: String
        public let type: String

        public init(_ newTypeName: String, _ type: String) {
            self.newTypeName = newTypeName
            self.type = type
        }
    }

    struct Field: ABICodable, Equatable, Hashable {
        public let name: String
        public let type: String

        public init(_ name: String, _ type: String) {
            self.name = name
            self.type = type
        }
    }

    struct Struct: ABICodable, Equatable, Hashable {
        public let name: String
        public let base: String
        public let fields: [Field]

        public init(_ name: String, _ fields: [Field]) {
            self.name = name
            self.base = ""
            self.fields = fields
        }

        public init(_ name: String, _ base: String, _ fields: [Field]) {
            self.name = name
            self.base = base
            self.fields = fields
        }
    }

    struct Action: ABICodable, Equatable, Hashable {
        public let name: Name
        public let type: String
        public let ricardianContract: String

        public init(_ nameAndType: Name, ricardian: String = "") {
            self.name = nameAndType
            self.type = String(nameAndType)
            self.ricardianContract = ricardian
        }

        public init(_ name: Name, _ type: String, ricardian: String = "") {
            self.name = name
            self.type = type
            self.ricardianContract = ricardian
        }
    }

    struct Table: ABICodable, Equatable, Hashable {
        public let name: Name
        public let indexType: String
        public let keyNames: [String]
        public let keyTypes: [String]
        public let type: String

        public init(_ name: Name, _ type: String, _ indexType: String, _ keyNames: [String] = [], _ keyTypes: [String] = []) {
            self.name = name
            self.type = type
            self.indexType = indexType
            self.keyNames = keyNames
            self.keyTypes = keyTypes
        }
    }

    struct Clause: ABICodable, Equatable, Hashable {
        public let id: String
        public let body: String

        public init(_ id: String, _ body: String) {
            self.id = id
            self.body = body
        }
    }

    struct Variant: ABICodable, Equatable, Hashable {
        public let name: String
        public let types: [String]

        public init(_ name: String, _ types: [String]) {
            self.name = name
            self.types = types
        }
    }

    private struct ErrorMessage: ABICodable, Equatable, Hashable {
        let errorCode: UInt64
        let errorMsg: String
    }
}

// MARK: ABI Coding

extension ABI: ABICodable {
    enum CodingKeys: String, CodingKey {
        // matches byte order
        case version
        case types
        case structs
        case actions
        case tables
        case ricardian_clauses
        case error_messages
        case abi_extensions
        case variants
    }

    public init(from decoder: Decoder) throws {
        // lenient decoding for poorly formed abi json files
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? "eosio::abi/1.1"
        self.types = try container.decodeIfPresent([ABI.TypeDef].self, forKey: .types) ?? []
        self.structs = try container.decodeIfPresent([ABI.Struct].self, forKey: .structs) ?? []
        self.actions = try container.decodeIfPresent([ABI.Action].self, forKey: .actions) ?? []
        self.tables = try container.decodeIfPresent([ABI.Table].self, forKey: .tables) ?? []
        self.ricardianClauses = try container.decodeIfPresent([ABI.Clause].self, forKey: .ricardian_clauses) ?? []
        self.variants = try container.decodeIfPresent([ABI.Variant].self, forKey: .variants) ?? []
    }

    public init(fromAbi decoder: ABIDecoder) throws {
        self.version = try decoder.decode(String.self)
        self.types = try decoder.decode([ABI.TypeDef].self)
        self.structs = try decoder.decode([ABI.Struct].self)
        self.actions = try decoder.decode([ABI.Action].self)
        self.tables = try decoder.decode([ABI.Table].self)
        self.ricardianClauses = try decoder.decode([ABI.Clause].self)
        _ = try decoder.decode([ABI.ErrorMessage].self) // ignore error messages, used only by abi compiler
        _ = try decoder.decode([Never].self) // abi extensions not used
        // decode variant typedefs (Y U NO USE EXTENSIONS?!)
        do {
            self.variants = try decoder.decode([ABI.Variant].self)
        } catch ABIDecoder.Error.prematureEndOfData {
            self.variants = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.types, forKey: .types)
        try container.encode(self.structs, forKey: .structs)
        try container.encode(self.actions, forKey: .actions)
        try container.encode(self.tables, forKey: .tables)
        try container.encode(self.ricardianClauses, forKey: .ricardian_clauses)
        try container.encode([] as [Never], forKey: .error_messages)
        try container.encode([] as [Never], forKey: .abi_extensions)
        try container.encode(self.variants, forKey: .variants)
    }
}

// MARK: ABI Defenition

extension ABI {
    /// The ABI defenition for the ABI defenition.
    public static let abi = ABI(structs: [
        ABI.Struct("extensions_entry", [
            ABI.Field("tag", "uint16"),
            ABI.Field("value", "bytes"),
        ]),
        ABI.Struct("type_def", [
            ABI.Field("new_type_name", "string"),
            ABI.Field("type", "string"),
        ]),
        ABI.Struct("field_def", [
            ABI.Field("name", "string"),
            ABI.Field("type", "string"),
        ]),
        ABI.Struct("struct_def", [
            ABI.Field("name", "string"),
            ABI.Field("base", "string"),
            ABI.Field("fields", "field_def[]"),
        ]),
        ABI.Struct("action_def", [
            ABI.Field("name", "name"),
            ABI.Field("type", "string"),
            ABI.Field("ricardian_contract", "string"),
        ]),
        ABI.Struct("table_def", [
            ABI.Field("name", "name"),
            ABI.Field("index_type", "string"),
            ABI.Field("key_names", "string[]"),
            ABI.Field("key_types", "string[]"),
            ABI.Field("type", "string"),
        ]),
        ABI.Struct("clause_pair", [
            ABI.Field("id", "string"),
            ABI.Field("body", "string"),
        ]),
        ABI.Struct("error_message", [
            ABI.Field("error_code", "uint64"),
            ABI.Field("error_msg", "string"),
        ]),
        ABI.Struct("variant_def", [
            ABI.Field("name", "string"),
            ABI.Field("types", "string[]"),
        ]),
        ABI.Struct("abi_def", [
            ABI.Field("version", "string"),
            ABI.Field("types", "type_def[]"),
            ABI.Field("structs", "struct_def[]"),
            ABI.Field("actions", "action_def[]"),
            ABI.Field("tables", "table_def[]"),
            ABI.Field("ricardian_clauses", "clause_pair[]"),
            ABI.Field("error_messages", "error_message[]"),
            ABI.Field("abi_extensions", "extensions_entry[]"),
            ABI.Field("variants", "variant_def[]$"),
        ]),
    ])
}