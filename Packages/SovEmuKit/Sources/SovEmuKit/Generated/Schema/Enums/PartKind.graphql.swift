// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

extension SovEmuGraphQL {
  /// What a multi-part game's files are.
  nonisolated enum PartKind: String, EnumType {
    /// Optical discs (CDs, DVDs, GD-ROMs).
    case disc = "DISC"
    /// Floppy disks (the Famicom Disk System's included).
    case disk = "DISK"
    /// Cassette tapes.
    case tape = "TAPE"
    /// The sides of one disk or tape.
    case side = "SIDE"
    /// Numbered files of any other kind.
    case part = "PART"
  }

}