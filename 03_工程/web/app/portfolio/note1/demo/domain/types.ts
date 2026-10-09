// NOTE1 Web 领域对象与错误。命名保留稳定业务含义，不带 iOS `V02` 历史前缀。
// 本文件及 engine.ts 不依赖 React、DOM 或 IndexedDB，可独立运行与测试。

export type ID = string;
export type ISODateTime = string;

export type CardFlowState = "visible" | "tuckedAway";
export type RoundState = "thinking" | "ended";
export type ResourceSource = "importedAttachment" | "voiceInspiration";
export type RoundEventKind =
  | "started"
  | "memberAdded"
  | "memberRemoved"
  | "inspirationEdited"
  | "ended";

export interface Inspiration {
  id: ID;
  text: string;
  cardFlowState: CardFlowState;
  collectionId: ID | null;
  createdAt: ISODateTime;
  updatedAt: ISODateTime;
  resourceIds: ID[];
}

export interface ThinkingCollection {
  id: ID;
  name: string;
  createdAt: ISODateTime;
  currentRoundId: ID | null;
  nextRoundNumber: number;
}

export interface RoundEvent {
  id: ID;
  kind: RoundEventKind;
  occurredAt: ISODateTime;
  inspirationId: ID | null;
}

export interface ThinkingRound {
  id: ID;
  collectionId: ID;
  state: RoundState;
  startedAt: ISODateTime;
  endedAt: ISODateTime | null;
  memberIds: ID[];
  effectiveEditCount: number;
  roundNumber: number;
  events: RoundEvent[];
}

export interface AttachmentResource {
  id: ID;
  source: ResourceSource;
  filename: string;
  mimeType: string;
  size: number;
  createdAt: ISODateTime;
}

export interface ReceiptSnapshotAttachment {
  id: ID;
  source: ResourceSource;
  filename: string;
  mimeType: string;
  size: number;
  createdAt: ISODateTime;
}

export interface ReceiptSnapshotMember {
  inspirationId: ID;
  text: string;
  resourceIds: ID[];
  attachments: ReceiptSnapshotAttachment[];
}

export interface ReceiptSnapshot {
  collectionName: string;
  startedAt: ISODateTime;
  endedAt: ISODateTime;
  roundNumber: number;
  effectiveEditCount: number;
  members: ReceiptSnapshotMember[];
  events: RoundEvent[];
}

export interface Receipt {
  id: ID;
  roundId: ID;
  collectionId: ID;
  createdAt: ISODateTime;
  snapshot: ReceiptSnapshot;
}

export type TrashObject =
  | { kind: "inspiration"; inspiration: Inspiration }
  | { kind: "receipt"; receipt: Receipt };

export interface TrashEntry {
  id: ID;
  object: TrashObject;
  deletedAt: ISODateTime;
}

export interface DomainState {
  version: number;
  nextCollectionNumber: number;
  inspirations: Inspiration[];
  collections: ThinkingCollection[];
  rounds: ThinkingRound[];
  resources: AttachmentResource[];
  receipts: Receipt[];
  trash: TrashEntry[];
}

export const DOMAIN_VERSION = 1;

export function emptyState(): DomainState {
  return {
    version: DOMAIN_VERSION,
    nextCollectionNumber: 1,
    inspirations: [],
    collections: [],
    rounds: [],
    resources: [],
    receipts: [],
    trash: [],
  };
}

export const MAX_RESOURCE_SIZE = 100 * 1024 * 1024; // 100 MB，与原生一致