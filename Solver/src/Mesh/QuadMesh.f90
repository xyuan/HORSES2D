module QuadMeshClass
    use SMConstants
    use NodeClass
    use QuadElementClass
    use InitialConditions
    use Storage_module
    use QuadMeshDefinitions

    private
    public QuadMesh_t , InitializeMesh

    type QuadMesh_t
         integer                               :: no_of_nodes
         integer                               :: no_of_edges
         integer                               :: no_of_elements
         class(Node_t),         pointer        :: nodes(:)
         class(Edge_p),         pointer        :: edges(:)           ! This is an array to pointers
         class(QuadElement_t) , pointer        :: elements(:)
         procedure(ICFcn)   , pointer , NOPASS :: IC
         contains
             procedure  :: ConstructFromFile
             procedure  :: SetInitialCondition
             procedure  :: ApplyInitialCondition
             procedure  :: SetStorage => QuadMesh_SetStorage
             procedure  :: VolumeIntegral => Compute_VolumeIntegral
    end type QuadMesh_t

    interface InitializeMesh
          module procedure newMesh
    end interface InitializeMesh

    contains
         function newMesh()
             implicit none
             type(QuadMesh_t)    :: newMesh
!
!            **************************
!            Set to zero all dimensions            
!            **************************
!
             newMesh % no_of_nodes = 0
             newMesh % no_of_edges = 0
             newMesh % no_of_elements = 0
!
!            **************************
!            Point all contents to NULL
!            **************************
!
             newMesh % nodes    => NULL()
             newMesh % edges    => NULL()
             newMesh % elements => NULL() 

         end function newMesh
!
!        *********************************************************************
!           Subroutine to build the mesh structure from the MeshFile_t
!              Class already loaded.
!        *********************************************************************
!
         subroutine constructFromFile( self , meshFile , spA , Storage , spI)
             use MeshFileClass
             use Setup_class
             use Physics
             use NodesAndWeights_Class
             implicit none
             class(QuadMesh_t),                 intent (out)                 :: self
             class(MeshFile_t),                 intent (in )                 :: meshFile
             class(NodalStorage),               intent (in )                 :: spA
             class(Storage_t),                  intent (in )                 :: storage
             class(NodesAndWeights_t), pointer, intent (in )                 :: spI
!            ----------------------------------------------------------------------
             integer                                                         :: node

!            **************
!            Set dimensions
!            **************
!
             self % no_of_nodes    = meshFile % no_of_nodes
             self % no_of_edges    = meshFile % no_of_edges
             self % no_of_elements = meshFile % no_of_elements
!
!            *********************
!            Allocate the contents
!            *********************
!
             allocate ( self % nodes    ( self % no_of_nodes    )  ) 
             allocate ( self % edges    ( self % no_of_edges    )  ) 
             allocate ( self % elements ( self % no_of_elements )  ) 
!
!            ***********************
!            Construct the contents
!            ***********************
!
!
!            ================
!            Construct nodes
!            ================
!
             do node = 1 , self % no_of_nodes
                 call self % nodes(node) % construct( ID = node, x = meshFile % points_coords(1:NDIM,node))
             end do
!
!            ============================
!            Construct edges and elements
!            ============================
!
             call constructElementsAndEdges( self , meshFile , spA, Storage , spI )

         end subroutine constructFromFile

         subroutine constructElementsAndEdges( self  , meshFile , spA , Storage , spI)
             use MeshFileClass
             use Setup_class
             use Physics
             use NodesAndWeights_Class
             implicit none
             class(QuadMesh_t),                 intent (inout)               :: self
             class(MeshFile_t),                 intent (in )                 :: meshFile
             class(NodalStorage),               intent (in )                 :: spA
             class(Storage_t),                  intent (in )                 :: storage
             class(NodesAndWeights_t), pointer, intent (in )                 :: spI
!            ----------------------------------------------------------------------
             integer                                  :: address
             integer                                  :: node
             integer                                  :: edge
             integer                                  :: eID
             integer                                  :: el1 , el2 , elb
             integer                                  :: curve
             type(Node_p)                             :: nodes(POINTS_PER_QUAD)
             class(QuadElement_t), pointer            :: leftE , rightE , bdryE
             logical                                  :: curvilinear
!            ----------------------------------------------------------------------
!
!            ===================
!            Construct elements
!            ===================
!
             do eID = 1 , self % no_of_elements
                 
                 do node = 1 , POINTS_PER_QUAD
                    nodes(node) % n => self % nodes ( meshFile % points_of_elements(node , eID) ) 
                 end do


                 address = ( meshFile % cumulativePolynomialOrder(eID-1)  ) * NEC + 1 
                 call self % elements(eID) % Construct( eID , nodes , meshFile % polynomialOrder(eID) , spA , address , storage , spI ) 

             end do

!
!            ================
!            Construct edges
!            ================
!
             do edge = 1 , self % no_of_edges

               do node = 1 , POINTS_PER_EDGE
                  nodes(node) % n => self % nodes ( meshFile % points_of_edges(node , edge) )
               end do

               if (meshFile % curvilinear) then
                  curvilinear = any(meshFile % curved_bdryedges == edge)
               else
                  curvilinear = .false.
               end if

               call self % edges(edge) % Construct( ID = edge , curvilinear = curvilinear , &
                                                nodes = nodes , edgeType = meshFile % edgeMarker(edge) , spA = spA , spI = spI )

               if (curvilinear) then
!
!              Add the curve to the edge
!              -------------------------
                  select type ( f => self % edges(edge) % f )

                     type is (Edge_t)
                        call self % edges(edge) % f % SetCurve()

                     type is (StraightBdryEdge_t) 
                        call self % edges(edge) % f % SetCurve()

                     type is (CurvedBdryEdge_t) 

                        curve = minloc(abs(meshFile % curved_bdryedges -  edge) , 1)
                        call self % edges(edge) % f % SetCurve( meshFile % curvilinear_coords(:,:,curve) , meshFile % curves_polynomialorder )  

                     class default

                  end select

               else
                  call self % edges(edge) % f % SetCurve()

               end if
             end do
!
!             ========================
!             Link elements with edges
!             ========================
!
              do edge = 1 , self % no_of_edges

                  if (self % edges(edge) % f % edgeType .eq. FACE_INTERIOR) then
                     el1 = meshFile % elements_of_edges( 1 , edge )
                     el2 = meshFile % elements_of_edges( 2 , edge )

                     call self % edges(edge) % linkWithElements( el1 = self % elements(el1) , el2 = self % elements(el2) )

                  else
                     
                     elb = meshFile % elements_of_edges( 1 , edge )
                     call self % edges(edge)  % linkWithElements( elb = self % elements(elb) )

                  end if
               end do

!
!              =================================
!              Compute the geometry of the quads
!              =================================
!
               do eID = 1 , self % no_of_elements
                  call self % elements(eID) % SetMappings
               end do
         end subroutine constructElementsAndEdges
           
         subroutine setInitialCondition( self )
             use InitialConditions
             implicit none
             class(QuadMesh_t)        :: self
!
!            *******************************
!            Get Initial Condition procedure              
!            *******************************
!
!             call InitialCondition( self % IC )
!
!            *******************************************
!            Apply the initial condition to the solution
!            *******************************************
!
             call self % applyInitialCondition()


          end subroutine setInitialCondition

          subroutine applyInitialCondition( self )
             use Physics
             implicit none
             class(QuadMesh_t)        :: self
             integer                  :: eID

             do eID = 1 , self % no_of_elements
                  self % elements(eID) % Q(:,:,1:NEC)  = 0.0_RP !self % IC( self % elements(eID) % x(j) ) 
             end do
             
          end subroutine applyInitialCondition

          subroutine QuadMesh_SetStorage( self , storage )
            use Storage_module
            implicit none
            class(QuadMesh_t)             :: self
            class(Storage_t)            :: storage
            integer                     :: eID

            do eID = 1 , self % no_of_elements
                call self % elements(eID) % SetStorage( storage )
            end do

         end subroutine QuadMesh_SetStorage

         function Compute_volumeIntegral( self , var ) result ( val )
            use MatrixOperations
            implicit none
            class(QuadMesh_T)          :: self
            character(len=*)           :: var
            real(kind=RP)              :: val
            real(kind=RP), allocatable :: variable(:,:)
!           ----------------------------------------------            
            integer                    :: eID
            
            val = 0.0_RP
            do eID = 1 , self % no_of_elements
               associate( e => self % elements(eID) )
               if ( trim(var) .eq. "One" ) then
                  if (allocated(variable) ) deallocate(variable)
                  allocate(variable(0:e % spA % N , 0:e % spA % N))
                  variable = 1.0_RP
               end if

               variable = variable * e % jac

               val = val + BilinearForm_F( variable , e % spA % w , e % spA % w ) 

               end associate
            end do
               
         end function Compute_volumeIntegral

end module QuadMeshClass   
