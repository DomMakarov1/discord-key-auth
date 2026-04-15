-- CreateTable
CREATE TABLE "ClientCommand" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "action" TEXT NOT NULL,
    "payload" JSONB,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lastDeliveredAt" TIMESTAMP(3),
    "acknowledgedAt" TIMESTAMP(3),
    "ackStatus" TEXT,
    "ackError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ClientCommand_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ClientCommand_userId_status_createdAt_idx" ON "ClientCommand"("userId", "status", "createdAt");

-- AddForeignKey
ALTER TABLE "ClientCommand" ADD CONSTRAINT "ClientCommand_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
