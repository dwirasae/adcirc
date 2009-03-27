subroutine SwanReadADCGrid
!
!   --|-----------------------------------------------------------|--
!     | Delft University of Technology                            |
!     | Faculty of Civil Engineering and Geosciences              |
!     | Environmental Fluid Mechanics Section                     |
!     | P.O. Box 5048, 2600 GA  Delft, The Netherlands            |
!     |                                                           |
!     | Programmer: Marcel Zijlema                                |
!   --|-----------------------------------------------------------|--
!
!
!     SWAN (Simulating WAves Nearshore); a third generation wave model
!     Copyright (C) 2008  Delft University of Technology
!
!     This program is free software; you can redistribute it and/or
!     modify it under the terms of the GNU General Public License as
!     published by the Free Software Foundation; either version 2 of
!     the License, or (at your option) any later version.
!
!     This program is distributed in the hope that it will be useful,
!     but WITHOUT ANY WARRANTY; without even the implied warranty of
!     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
!     GNU General Public License for more details.
!
!     A copy of the GNU General Public License is available at
!     http://www.gnu.org/copyleft/gpl.html#SEC3
!     or by writing to the Free Software Foundation, Inc.,
!     59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
!
!
!   Authors
!
!   40.80: Marcel Zijlema
!   40.95: Marcel Zijlema
!
!   Updates
!
!   40.80, December 2007: New subroutine
!   40.95,     June 2008: parallelization of unSWAN using MESSENGER of ADCIRC
!
!   Purpose
!
!   Reads ADCIRC grid described in fort.14
!
!   Method
!
!   Grid coordinates of vertices are read from file fort.14 and stored in Swan data structure
!   Vertices of triangles are read from file fort.14 and stored in Swan data structure
!
!   Bottom topography from file fort.14 will also be stored
!
!   Modules used
!
    use ocpcomm2
    use ocpcomm4
    use m_genarr
    use SwanGriddata
    use SIZES
    use MESSENGER
!Casey 081112: Add modules for obstacles.
    use M_OBSTA
    use swcomm3, only: NUMOBS
!
    implicit none
!
!   Local variables
!
    character(80)           :: grdfil   ! name of grid file including path
    integer, save           :: ient = 0 ! number of entries in this subroutine
    integer                 :: idum     ! dummy integer
    integer                 :: ii       ! auxiliary integer
    integer                 :: iostat   ! I/O status in call FOR
    integer                 :: istat    ! indicate status of allocation
    integer                 :: ivert    ! vertex index
    integer                 :: j        ! loop counter
    integer                 :: k        ! loop counter
    integer                 :: n1       ! auxiliary integer
    integer                 :: n2       ! another auxiliary integer
    integer                 :: ndsd     ! unit reference number of file
    integer                 :: vm       ! boundary marker
    character(80)           :: line     ! auxiliary textline
    logical                 :: stpnow   ! indicate whether program must be terminated or not
!Casey 081111: Add some variables for the levees.
    real(8)                 :: area
    integer, allocatable    :: DummyElems(:,:)
    integer, allocatable    :: ivert1(:)
    integer, allocatable    :: ivert2(:)
    real(8)                 :: LeveeHeight
    integer                 :: NumDummyElems = 0
    integer, allocatable    :: TempElems(:,:)
    real(8)                 :: x1, x2, x3, y1, y2, y3
!Casey 081112: Added more variables for the obstacles.
    TYPE(OBSTDAT),POINTER      :: OBSTMP
    TYPE(OBSTDAT),SAVE,POINTER :: COBST
    INTEGER                    :: ITRAS
    INTEGER                    :: LREF
    INTEGER                    :: LREFDIFF
    INTEGER                    :: LRFRD
    LOGICAL,SAVE               :: LOBST = .FALSE.
!Casey 090304: Added even more variables for reading of boundary information.
    INTEGER                    :: bdrytype
    INTEGER                    :: numopenbdry
    LOGICAL                    :: Parallel
!
!   Structure
!
!   Description of the pseudo code
!
!   Source text
!
    if (ltrace) call strace (ient,'SwanReadADCGrid')
    !
    ! open file fort.14
    !
    ndsd   = 0
    iostat = 0
    grdfil = 'fort.14'
    grdfil = trim(INPUTDIR)//DIRCH2//trim(grdfil)
    call for (ndsd, grdfil, 'OF', iostat)
    if (stpnow()) goto 900
    !
    ! skip first line
    !
    read(ndsd,'(a80)', end=950, err=910) line
    !
    ! read number of elements and number of vertices
    !
    read(ndsd, *, end=950, err=910) ncells, nverts
    if(.not.allocated(xcugrd)) allocate (xcugrd(nverts), stat = istat)
    if ( istat == 0 ) then
       if(.not.allocated(ycugrd)) allocate (ycugrd(nverts), stat = istat)
    endif
    if ( istat == 0 ) then
       if(.not.allocated(DEPTH)) allocate (DEPTH(nverts), stat = istat)
    endif
    if ( istat /= 0 ) then
       call msgerr ( 4, 'Allocation problem in SwanReadADCGrid: array xcugrd, ycugrd or depth ' )
       goto 900
    endif
    !
    ! read coordinates of vertices and bottom topography
    !
    do j = 1, nverts
       read(ndsd, *, end=950, err=910) ii, xcugrd(ii), ycugrd(ii), DEPTH(ii)
       if ( ii/=j ) call msgerr ( 1, 'numbering of vertices is not sequential in grid file fort.14 ' )
    enddo
    !
    if(.not.allocated(kvertc)) allocate (kvertc(3,ncells), stat = istat)
    if ( istat /= 0 ) then
       call msgerr ( 4, 'Allocation problem in SwanReadADCGrid: array kvertc ' )
       goto 900
    endif
    !
    ! read vertices of triangles
    !
    do j = 1, ncells
       read(ndsd, *, end=950, err=910) ii, idum, kvertc(1,ii), kvertc(2,ii), kvertc(3,ii)
       if ( ii/=j ) call msgerr ( 1, 'numbering of triangles is not sequential in grid file fort.14 ' )
    enddo
    !
!Casey 090304: Instead of skipping the standard ADCIRC boundary information
!              and then reading a modified version of it at the end of the file,
!              let's just grab the information from the standard list.
!   ! skip part containing ADCIRC boundary information (not relevant to SWAN)
!   !
!   read(ndsd, *, end=950, err=910) n1
!   read(ndsd, *, end=950, err=910) idum
!   do j = 1, n1
!      read(ndsd, *, end=950, err=910) n2
!      do k = 1, n2
!         read(ndsd, *, end=950, err=910) idum
!      enddo
!   enddo
!   !
!   read(ndsd, *, end=950, err=910) n1
!   read(ndsd, *, end=950, err=910) idum
!   do j = 1, n1
!      read(ndsd, *, end=950, err=910) n2, idum
!      do k = 1, n2
!         read(ndsd, *, end=950, err=910) idum
!      enddo
!   enddo
    !
    if(.not.allocated(vmark)) allocate (vmark(nverts), stat = istat)
    if ( istat /= 0 ) then
       call msgerr ( 4, 'Allocation problem in SwanReadADCGrid: array vmark ' )
       goto 900
    endif
    vmark = 0
    !
    ! read and store boundary markers
    !
    Parallel = .FALSE.
    Parallel = .TRUE.
    !
    read(ndsd, *, end=950, err=910) numopenbdry
    read(ndsd, *, end=950, err=910) idum
    do j = 1, numopenbdry
       if ( .not.Parallel ) then
          read(ndsd, *, end=950, err=910) n2
          vm = j
       else
          read(ndsd, *, end=950, err=910) n2, vm
       endif
       do k = 1, n2
          read(ndsd, *, end=950, err=910) ivert
          vmark(ivert) = vm
       enddo
    enddo
    !
    read(ndsd, *, end=950, err=910) n1
    read(ndsd, *, end=950, err=910) idum
    do j = 1, n1
       if ( .not.Parallel ) then
          read(ndsd, *, end=950, err=910) n2, bdrytype
          vm = numopenbdry + j
       else
          read(ndsd, *, end=950, err=910) n2, bdrytype, vm
       endif
       if((bdrytype.ne.4).and.(bdrytype.ne.24))then 
          do k = 1, n2
             read(ndsd, *, end=950, err=910) ivert
             vmark(ivert) = vm
          enddo
       else
!Casey 081111: Adjust for levees.
!... Allocate arrays for reading the levee node pairs.
          allocate(ivert1(1:n2))
          allocate(ivert2(1:n2))
!... Allocate an array to contain the dummy elements inside the levee.
          if(.not.allocated(DummyElems)) allocate(DummyElems(1:3,1:ncells))
!... Allocate and initialize a temporary array for a new obstacle.
          ALLOCATE(OBSTMP)
          OBSTMP%TRCOEF(1) = 0.
          OBSTMP%TRCOEF(2) = 0.
          OBSTMP%TRCOEF(3) = 0.
          OBSTMP%RFCOEF(1) = 0.
          OBSTMP%RFCOEF(2) = 0.
          OBSTMP%RFCOEF(3) = 0.
          OBSTMP%RFCOEF(4) = 0.
          OBSTMP%RFCOEF(5) = 0.
          OBSTMP%RFCOEF(6) = 0.
!... Allow no transmission through the obstacle.
          ITRAS = 1
          IF(ITRAS.EQ.0)THEN
             OBSTMP%TRCOEF(1) = 0.       ! Transmission coefficient.
          ELSEIF(ITRAS.EQ.1)THEN
             OBSTMP%TRCOEF(1) =  10.     ! Levee height.
             OBSTMP%TRCOEF(2) = 1.8      ! Alpha.
             OBSTMP%TRCOEF(3) = 0.1      ! Beta.
          ENDIF
          OBSTMP%TRTYPE = ITRAS
!... Allow pure reflection from the obstacle.
          LREF = 1
          OBSTMP%RFCOEF(1) = 0.          ! Reflection coefficient.
          LREFDIFF = 0
          OBSTMP%RFTYP2 = LREFDIFF
          LRFRD = 0
          OBSTMP%RFTYP3 = LRFRD
! ... Initialize stuff for the line of x,y points in the obstacle.
          OBSTMP%NCRPTS = n2
          ALLOCATE(OBSTMP%XCRP(n2))
          ALLOCATE(OBSTMP%YCRP(n2))
! ... Read vertices and levee height.
          do k = 1, n2
             read(ndsd, *, end=950, err=910) ivert1(k), ivert2(k), LeveeHeight
!... Assign the levee nodes as boundary nodes.
             vmark(ivert1(k)) = vm
             vmark(ivert2(k)) = vm
!... Add dummy elements inside the levee.
             if(k.gt.1)then
                NumDummyElems = NumDummyElems + 1
                x1 = xcugrd(ivert1(k-1))
                x2 = xcugrd(ivert2(k-1))
                x3 = xcugrd(ivert1(k  ))
                y1 = ycugrd(ivert1(k-1))
                y2 = ycugrd(ivert2(k-1))
                y3 = ycugrd(ivert1(k  ))
                area = (x2*y3-x3*y2)-(x1*y3-x3*y1)+(x1*y2-x2*y1)
                if(area.gt.0.)then
                   DummyElems(1,NumDummyElems) = ivert1(k-1)
                   DummyElems(2,NumDummyElems) = ivert2(k-1)
                   DummyElems(3,NumDummyElems) = ivert1(k)
                else
                   DummyElems(1,NumDummyElems) = ivert1(k-1)
                   DummyElems(2,NumDummyElems) = ivert1(k)
                   DummyElems(3,NumDummyElems) = ivert2(k-1)
                endif
                NumDummyElems = NumDummyElems + 1
                x1 = xcugrd(ivert2(k-1))
                x2 = xcugrd(ivert1(k  ))
                x3 = xcugrd(ivert2(k  ))
                y1 = ycugrd(ivert2(k-1))
                y2 = ycugrd(ivert1(k  ))
                y3 = ycugrd(ivert2(k  ))
                area = (x2*y3-x3*y2)-(x1*y3-x3*y1)+(x1*y2-x2*y1)
                if(area.gt.0.)then
                   DummyElems(1,NumDummyElems) = ivert2(k-1)
                   DummyElems(2,NumDummyElems) = ivert1(k)
                   DummyElems(3,NumDummyElems) = ivert2(k)
                else
                   DummyElems(1,NumDummyElems) = ivert2(k-1)
                   DummyElems(2,NumDummyElems) = ivert2(k)
                   DummyElems(3,NumDummyElems) = ivert1(k)
                endif
             endif
!... Assign the line of x,y points inside the obstacle.
             OBSTMP%XCRP(k) = 0.5 * (xcugrd(ivert1(k)) + xcugrd(ivert2(k)))
             OBSTMP%YCRP(k) = 0.5 * (ycugrd(ivert1(k)) + ycugrd(ivert2(k)))
          enddo
!... Finish setting up the obstacle.
          NUMOBS = NUMOBS + 1
          NULLIFY(OBSTMP%NEXTOBST)
          IF( .NOT.LOBST )THEN
             FOBSTAC = OBSTMP
             COBST => FOBSTAC
             LOBST = .TRUE.
          ELSE
             COBST%NEXTOBST => OBSTMP
             COBST => OBSTMP
          ENDIF
!... Deallocate arrays for levee node pairs.
          deallocate(ivert1)
          deallocate(ivert2)
       endif
    enddo
    !
    ! close file fort.14
    !
    close(ndsd)
    !
!Casey 081111: Add dummy elements inside the ADCIRC levees.
    if( NumDummyElems.gt.0 .and. .FALSE. )then
       allocate (TempElems(1:3,1:ncells))
       do ii = 1, ncells
          TempElems(1,ii) = kvertc(1,ii)
          TempElems(2,ii) = kvertc(2,ii)
          TempElems(3,ii) = kvertc(3,ii)
       enddo
       if(allocated(kvertc)) deallocate(kvertc)
       if(.not.allocated(kvertc)) allocate (kvertc(3,ncells+NumDummyElems), stat = istat)
       if ( istat /= 0 ) then
          call msgerr ( 4, 'Allocation problem in SwanReadADCGrid: array kvertc ' )
          goto 900
       endif
       do ii = 1, ncells
          kvertc(1,ii) = TempElems(1,ii)
          kvertc(2,ii) = TempElems(2,ii)
          kvertc(3,ii) = TempElems(3,ii)
       enddo
       do ii = 1, NumDummyElems
          kvertc(1,ii+ncells) = DummyElems(1,ii)
          kvertc(2,ii+ncells) = DummyElems(2,ii)
          kvertc(3,ii+ncells) = DummyElems(3,ii)
       enddo
       ncells = ncells + NumDummyElems
       if(allocated(DummyElems)) deallocate(DummyElems)
       if(allocated(TempElems))  deallocate(TempElems)
    endif
    !
       ! ghost vertices are marked with +999
       !
       do j = 1, NEIGHPROC
          do k = 1, NNODRECV(j)
             ivert = IRECVLOC(k,j)
             vmark(ivert) = 999
          enddo
       enddo
       !
 900 return
    !
 910 call msgerr (4, 'error reading data from grid file fort.14' )
    goto 900
 950 call msgerr (4, 'unexpected end of file in grid file fort.14' )
    goto 900
    !
end subroutine SwanReadADCGrid
